# Operations

## Scale nodegroup
```bash
aws eks update-nodegroup-config \
  --region eu-west-1 --cluster-name eks-mini-cluster --nodegroup-name eks-mini-cluster-ng \
  --scaling-config minSize=1,maxSize=3,desiredSize=3
```

## Rotate API endpoint CIDRs (lock public to your IP)
```bash
MYIP=$(curl -s https://checkip.amazonaws.com)/32
aws eks update-cluster-config --name eks-mini-cluster --region eu-west-1 \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs="[$MYIP]"
```
