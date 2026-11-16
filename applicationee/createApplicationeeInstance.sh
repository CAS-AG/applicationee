aws login
aws ec2 create-security-group \
  --group-name 'applicationee-security-group' \
  --description 'applicationee-security-group' --vpc-id 'vpc-00c309188b0857b7b'
aws ec2 authorize-security-group-ingress \
  --group-id 'sg-0c919c8d53d89382c' \
  --ip-permissions '{"IpProtocol":"tcp","FromPort":22,"ToPort":22,"IpRanges":[{"CidrIp":"194.49.64.241/32"}]}'
aws ec2 run-instances \
  --image-id 'ami-0303e2e4a29f041a3' \
  --instance-type 't3.micro' \
  --ebs-optimized \
  --block-device-mappings '{"DeviceName":"/dev/sda1","Ebs":{"Encrypted":true,"DeleteOnTermination":true,"Iops":3000,"SnapshotId":"snap-072ea95997b7021c5","VolumeSize":8,"VolumeType":"gp3","Throughput":125}}' \
  --network-interfaces '{"SubnetId":"subnet-08cfe99f09d5c5145","AssociatePublicIpAddress":false,"DeviceIndex":0,"Groups":["sg-0c919c8d53d89382c"]}' \
  --credit-specification '{"CpuCredits":"unlimited"}' \
  --metadata-options '{"HttpEndpoint":"enabled","HttpPutResponseHopLimit":2,"HttpTokens":"required"}' \
  --private-dns-name-options '{"HostnameType":"ip-name","EnableResourceNameDnsARecord":false,"EnableResourceNameDnsAAAARecord":false}' \
  --count '1'
