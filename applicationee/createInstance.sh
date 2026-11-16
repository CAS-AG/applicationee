#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---------------------------------------------------------
VPC_ID='vpc-00c309188b0857b7b'
SUBNET_ID='subnet-08cfe99f09d5c5145'
IMAGE_ID='ami-0303e2e4a29f041a3'
SG_NAME='applicationee-security-group'
# Hamburg offices ip
SSH_CIDR='194.49.64.241/32'
# 4 GB RAM, enough for Claude Code, builds and MongoDB. The AMI is x86, so
# Graviton types (t4g) do not fit.
INSTANCE_TYPE='t3.micro'
ROOT_VOLUME_SIZE=8
# Shown in the Name column of the EC2 console.
INSTANCE_NAME='CAS AG Consultant Applicationee'
# This keypair was once used for another project. It
# resides in the "instana" 1Password vault.
KEY_NAME='Instana'
EIP_ALLOCATION_ID='eipalloc-0bf92491652d65e7d'   # 52.57.229.14
# Default user of the Ubuntu AMI.
SSH_USER='ubuntu'
# Private key of the "Instana" key pair; override with KEY_FILE=... if stored elsewhere.
KEY_FILE="${KEY_FILE:-$HOME/.ssh/Instana.pem}"
# GITHUB_REPO='CAS-AG/'
# Where provision/ is placed on the instance.
PROVISION_DIR='/opt/applicationee-provision'
# Separate EBS volume that outlives the instance: it is found by this Name
# tag, created on the first run and attached again to every new instance.
# deleteInstance.sh asks whether to keep it.
DATA_VOLUME_NAME='CAS AG Applicationee Data'
DATA_VOLUME_SIZE=8
DATA_DEVICE='/dev/sdf'
DATA_MOUNT='/data'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

# --- Local prerequisites ---------------------------------------------------
if [[ ! -r "${KEY_FILE}" ]]; then
  echo "Private key ${KEY_FILE} not found. Export it from 1Password or set KEY_FILE." >&2
  exit 1
fi

# Adding a deploy key needs gh signed in with admin rights on the repo.
if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not installed or not signed in. Run 'gh auth login' first." >&2
  exit 1
fi
if [[ "$(gh api "repos/${GITHUB_REPO}" --jq .permissions.admin)" != "true" ]]; then
  echo "Your GitHub account has no admin rights on ${GITHUB_REPO}, which adding a deploy key requires." >&2
  exit 1
fi

aws login

# Fail early if the key pair is missing in this region.
aws ec2 describe-key-pairs --key-names "${KEY_NAME}" --query 'KeyPairs[0].KeyName' --output text >/dev/null

# Fail early if the Elastic IP is already attached, so no instance is left
# running without it.
EIP_ASSOCIATION=$(aws ec2 describe-addresses --allocation-ids "${EIP_ALLOCATION_ID}" \
  --query 'Addresses[0].AssociationId' --output text)
if [[ -n "${EIP_ASSOCIATION}" && "${EIP_ASSOCIATION}" != "None" ]]; then
  EIP_OWNER=$(aws ec2 describe-addresses --allocation-ids "${EIP_ALLOCATION_ID}" \
    --query 'Addresses[0].[InstanceId,NetworkInterfaceId]' --output text)
  echo "Elastic IP ${EIP_ALLOCATION_ID} is already associated (${EIP_OWNER}). Aborting." >&2
  exit 1
fi

# --- Security group --------------------------------------------------------
# Reuse the group if it already exists in the VPC, otherwise create it and
# take the GroupId from the response.
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [[ -z "${SG_ID}" || "${SG_ID}" == "None" ]]; then
  SG_ID=$(aws ec2 create-security-group \
    --group-name "${SG_NAME}" \
    --description "${SG_NAME}" \
    --vpc-id "${VPC_ID}" \
    --query 'GroupId' --output text)
  echo "Created security group ${SG_ID}"

  aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --ip-permissions "{\"IpProtocol\":\"tcp\",\"FromPort\":22,\"ToPort\":22,\"IpRanges\":[{\"CidrIp\":\"${SSH_CIDR}\"}]}"
else
  echo "Using existing security group ${SG_ID}"
fi

# --- Data volume -----------------------------------------------------------
# A volume can only be attached to an instance in its own availability zone,
# which SUBNET_ID decides.
AVAILABILITY_ZONE=$(aws ec2 describe-subnets --subnet-ids "${SUBNET_ID}" \
  --query 'Subnets[0].AvailabilityZone' --output text)

read -r DATA_VOLUME_ID DATA_VOLUME_AZ DATA_VOLUME_STATE <<< "$(aws ec2 describe-volumes \
  --filters "Name=tag:Name,Values=${DATA_VOLUME_NAME}" \
  --query 'Volumes[0].[VolumeId,AvailabilityZone,State]' --output text)"

if [[ -z "${DATA_VOLUME_ID}" || "${DATA_VOLUME_ID}" == "None" ]]; then
  DATA_VOLUME_ID=$(aws ec2 create-volume \
    --volume-type gp3 \
    --size "${DATA_VOLUME_SIZE}" \
    --availability-zone "${AVAILABILITY_ZONE}" \
    --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${DATA_VOLUME_NAME}}]" \
    --query 'VolumeId' --output text)
  aws ec2 wait volume-available --volume-ids "${DATA_VOLUME_ID}"
  echo "Created data volume ${DATA_VOLUME_ID} (${DATA_VOLUME_SIZE} GB)"
elif [[ "${DATA_VOLUME_AZ}" != "${AVAILABILITY_ZONE}" ]]; then
  echo "Data volume ${DATA_VOLUME_ID} is in ${DATA_VOLUME_AZ}, but the instance will be in ${AVAILABILITY_ZONE}. Aborting." >&2
  exit 1
elif [[ "${DATA_VOLUME_STATE}" != "available" ]]; then
  echo "Data volume ${DATA_VOLUME_ID} is ${DATA_VOLUME_STATE}, probably still attached to the old instance. Run ./deleteInstance.sh first. Aborting." >&2
  exit 1
else
  echo "Using existing data volume ${DATA_VOLUME_ID}"
fi

# --- Values derived from the AMI -------------------------------------------
# Root device name and snapshot belong to the AMI, so read them from it
# instead of hardcoding.
ROOT_DEVICE=$(aws ec2 describe-images --image-ids "${IMAGE_ID}" \
  --query 'Images[0].RootDeviceName' --output text)
SNAPSHOT_ID=$(aws ec2 describe-images --image-ids "${IMAGE_ID}" \
  --query "Images[0].BlockDeviceMappings[?DeviceName=='${ROOT_DEVICE}'].Ebs.SnapshotId | [0]" --output text)

# --- User data -------------------------------------------------------------
# Runs as root on first boot. It writes provision/ to PROVISION_DIR on the
# instance and runs all its steps (see provision/run.sh): base packages,
# Claude Code, a GitHub deploy key, rootless Docker and Node.js. The clone
# happens later, once the deploy key is registered with GitHub. provision.sh
# reruns steps on a running instance from the same files.
USER_DATA="${WORK_DIR}/user-data.sh"
{
  echo '#!/bin/bash'
  echo 'set -euxo pipefail'
  echo "mkdir -p ${PROVISION_DIR}/steps"
  for path in "${SCRIPT_DIR}"/provision/run.sh "${SCRIPT_DIR}"/provision/steps/*.sh; do
    f="${path#"${SCRIPT_DIR}/provision/"}"
    if grep -qx 'PROVISION_FILE' "${path}"; then
      echo "provision/${f} contains the heredoc delimiter PROVISION_FILE." >&2
      exit 1
    fi
    echo "cat > ${PROVISION_DIR}/${f} <<'PROVISION_FILE'"
    cat "${path}"
    echo 'PROVISION_FILE'
  done
  echo "chmod 755 ${PROVISION_DIR}/run.sh"
  echo "${PROVISION_DIR}/run.sh '${SSH_USER}'"
} > "${USER_DATA}"

# --- Instance --------------------------------------------------------------
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${IMAGE_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --key-name "${KEY_NAME}" \
  --ebs-optimized \
  --block-device-mappings "{\"DeviceName\":\"${ROOT_DEVICE}\",\"Ebs\":{\"Encrypted\":false,\"DeleteOnTermination\":true,\"Iops\":3000,\"SnapshotId\":\"${SNAPSHOT_ID}\",\"VolumeSize\":${ROOT_VOLUME_SIZE},\"VolumeType\":\"gp3\",\"Throughput\":125}}" \
  --network-interfaces "{\"SubnetId\":\"${SUBNET_ID}\",\"AssociatePublicIpAddress\":false,\"DeviceIndex\":0,\"Groups\":[\"${SG_ID}\"]}" \
  --credit-specification '{"CpuCredits":"unlimited"}' \
  --metadata-options '{"HttpEndpoint":"enabled","HttpPutResponseHopLimit":2,"HttpTokens":"required"}' \
  --private-dns-name-options '{"HostnameType":"ip-name","EnableResourceNameDnsARecord":false,"EnableResourceNameDnsAAAARecord":false}' \
  --user-data "file://${USER_DATA}" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
    "ResourceType=volume,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
  --count 1 \
  --query 'Instances[0].InstanceId' --output text)

echo "Launched instance ${INSTANCE_ID}"

# From here on the instance exists; on failure, say so instead of leaving it
# running silently.
fail_after_launch() {
  echo "$1" >&2
  echo "Instance ${INSTANCE_ID} is still running; terminate it with:" >&2
  echo "  aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}" >&2
  exit 1
}

# --- Elastic IP ------------------------------------------------------------
# The address can only be associated once the instance is running.
aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"

if ! ASSOCIATION_ID=$(aws ec2 associate-address \
  --instance-id "${INSTANCE_ID}" \
  --allocation-id "${EIP_ALLOCATION_ID}" \
  --query 'AssociationId' --output text); then
  fail_after_launch "Failed to associate Elastic IP ${EIP_ALLOCATION_ID} with ${INSTANCE_ID}."
fi

PUBLIC_IP=$(aws ec2 describe-addresses --allocation-ids "${EIP_ALLOCATION_ID}" \
  --query 'Addresses[0].PublicIp' --output text)

echo "Associated Elastic IP ${PUBLIC_IP} (${ASSOCIATION_ID}) with ${INSTANCE_ID}"

# Volumes attached after launch are not deleted when the instance terminates.
aws ec2 attach-volume --volume-id "${DATA_VOLUME_ID}" --instance-id "${INSTANCE_ID}" \
  --device "${DATA_DEVICE}" >/dev/null \
  || fail_after_launch "Failed to attach data volume ${DATA_VOLUME_ID} to ${INSTANCE_ID}."
aws ec2 wait volume-in-use --volume-ids "${DATA_VOLUME_ID}" \
  || fail_after_launch "Data volume ${DATA_VOLUME_ID} did not get attached."
echo "Attached data volume ${DATA_VOLUME_ID}"

# --- Provisioning over SSH -------------------------------------------------
# A throwaway known_hosts file: the Elastic IP is reused across instances, so
# its host key changes with every new instance.
SSH_OPTS=(-i "${KEY_FILE}" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new
          -o UserKnownHostsFile="${WORK_DIR}/known_hosts")
remote() { ssh "${SSH_OPTS[@]}" "${SSH_USER}@${PUBLIC_IP}" "$@"; }

echo "Waiting for SSH on ${PUBLIC_IP} ..."
for _ in $(seq 36); do
  remote true 2>/dev/null && break
  sleep 5
done
remote true || fail_after_launch "SSH to ${SSH_USER}@${PUBLIC_IP} did not come up."

echo "Waiting for cloud-init to finish ..."
# Exit code 2 means "done with recoverable errors", which is not fatal here.
CLOUD_INIT_RC=0
remote 'cloud-init status --wait' || CLOUD_INIT_RC=$?
if [[ ${CLOUD_INIT_RC} -eq 2 ]]; then
  echo "cloud-init finished with warnings; see /var/log/cloud-init-output.log on the instance." >&2
elif [[ ${CLOUD_INIT_RC} -ne 0 ]]; then
  fail_after_launch "cloud-init failed; see /var/log/cloud-init-output.log on the instance."
fi

remote 'docker info >/dev/null && node --version >/dev/null' \
  || fail_after_launch "Docker or Node.js does not work; see /var/log/cloud-init-output.log on the instance."

# On Nitro instances the volume shows up as an NVMe device, not as
# DATA_DEVICE; the stable name contains the volume ID. A new volume is
# formatted, one with a file system is mounted as it is.
remote "sudo bash -s -- '${DATA_VOLUME_ID}' '${DATA_MOUNT}' '${SSH_USER}'" <<'MOUNT' \
  || fail_after_launch "Mounting data volume ${DATA_VOLUME_ID} on ${DATA_MOUNT} failed."
set -euo pipefail
volume_id=$1 mount_point=$2 owner=$3
device="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${volume_id//-/}"
for _ in $(seq 30); do
  [[ -e "${device}" ]] && break
  sleep 2
done
[[ -e "${device}" ]] || { echo "Device ${device} not found." >&2; exit 1; }
if ! blkid "${device}" >/dev/null; then
  mkfs.ext4 -q -L edidata "${device}"
fi
uuid=$(blkid -s UUID -o value "${device}")
[[ -n "${uuid}" ]] || { echo "${device} has no file system UUID." >&2; exit 1; }
grep -q "^UUID=${uuid} " /etc/fstab \
  || echo "UUID=${uuid} ${mount_point} ext4 defaults,nofail 0 2" >> /etc/fstab
mkdir -p "${mount_point}"
mountpoint -q "${mount_point}" || mount "${mount_point}"
chown "${owner}:${owner}" "${mount_point}"
# Only on first use: later the mongo container owns this directory.
if [[ ! -d "${mount_point}/mongo" ]]; then
  install -d -o "${owner}" -g "${owner}" "${mount_point}/mongo"
fi
MOUNT

DEPLOY_KEY_TITLE="ec2-${INSTANCE_ID}"
remote 'cat ~/.ssh/github_deploy.pub' > "${WORK_DIR}/github_deploy.pub" \
  || fail_after_launch "Could not read the deploy key from the instance."
# With write access, so the instance can push.
gh repo deploy-key add "${WORK_DIR}/github_deploy.pub" --repo "${GITHUB_REPO}" --title "${DEPLOY_KEY_TITLE}" --allow-write \
  || fail_after_launch "Could not add the deploy key to ${GITHUB_REPO}."

remote "git clone git@github.com:${GITHUB_REPO}.git" \
  || fail_after_launch "git clone of ${GITHUB_REPO} failed."

cat <<SUMMARY

Instance ${INSTANCE_ID} is ready.
  Connect:    ssh -i ${KEY_FILE} ${SSH_USER}@${PUBLIC_IP}
              (if ssh warns about a changed host key: ssh-keygen -R ${PUBLIC_IP})
  Repository: ~/edimaestro (deploy key "${DEPLOY_KEY_TITLE}" with write access)
  Claude:     run 'claude' once on the instance to sign in.
  Docker:     rootless, runs as ${SSH_USER} (systemctl --user status docker)
  Node.js:    $(remote 'node --version')
  Setup:      ${PROVISION_DIR}; rerun steps with ./provision.sh
  Data:       ${DATA_MOUNT} on volume ${DATA_VOLUME_ID} "${DATA_VOLUME_NAME}"; MongoDB data goes to ${DATA_MOUNT}/mongo

Delete the instance with ./deleteInstance.sh. It removes the deploy key and
asks whether to keep the data volume.
SUMMARY
