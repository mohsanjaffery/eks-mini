# eks-mini — Minimal EKS (free-tier friendly)

This repo deploys a tiny, low-cost Amazon EKS cluster and a sample app exposed via an internet-facing **NLB**.

**What you get**
- VPC with two public subnets (tagged for k8s LoadBalancers)
- EKS cluster v1.30 with managed add-ons (VPC CNI, CoreDNS, kube-proxy)
- Managed node group on **ARM** (`t4g.micro`)
- Sample NGINX app exposed by `Service type=LoadBalancer` (NLB). We use a fixed NodePort **31080**, so the SG rule doesn’t flap.

> Cost note: EKS control plane and NLB incur charges. Nodes are tiny to minimize cost; no NAT Gateways.

## Prereqs (macOS)

```bash
brew install awscli kubectl jq rain
```

- AWS account with permissions for CloudFormation, EKS, ELBv2, EC2, and `iam:PassRole`/`iam:CreateServiceLinkedRole`.

## Quick start

```bash
# variables
export REGION=eu-west-1
export STACK=eks-mini-stack
export CLUSTER=eks-mini-cluster
export TEMPLATE=infra/cloudformation/eks-mini.json

# 1) deploy the stack (open CIDR for creation; lock down later)
rain deploy "$TEMPLATE" "$STACK" -r "$REGION" -y \
  --params ClusterName=$CLUSTER,KubernetesVersion=1.30,NodeInstanceType=t4g.micro,DesiredSize=2,MinSize=1,MaxSize=2,NodeVolumeSizeGiB=20,PublicAccessCidrs=0.0.0.0/0

# 2) kubeconfig
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl get nodes -o wide

# 3) deploy the sample app (NLB)
make app-apply
```

Open port **31080** on your worker & cluster security groups once (fixed NodePort):

```bash
# Worker SGs
ALL_SGS=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:eks:cluster-name,Values=$CLUSTER" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].SecurityGroups[].GroupId' --output text | tr '\t' '\n' | sort -u)
for SG in $ALL_SGS; do
  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG" --protocol tcp --port 31080 --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
done
# Cluster SG
CLUSTER_SG=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$CLUSTER_SG" --protocol tcp --port 31080 --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
```

Get the URL:
```bash
ELB_HOST=$(kubectl -n demo get svc/hello -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
open "http://$ELB_HOST"
```

**Lock down** the API after nodes join:
```bash
MYIP=$(curl -s https://checkip.amazonaws.com)/32
aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs="[$MYIP]"
```

## Troubleshooting

- **Pending pods / “Too many pods”** on a single `t4g.micro`:
  - Scale CoreDNS down to 1: `kubectl -n kube-system scale deployment coredns --replicas=1`, or
  - Add a second node:  
    `aws eks update-nodegroup-config --region "$REGION" --cluster-name "$CLUSTER" --nodegroup-name "${CLUSTER}-ng" --scaling-config minSize=1,maxSize=2,desiredSize=2`
- **NLB unhealthy**: ensure the Service has endpoints (`kubectl -n demo get endpoints hello`), NodePort 31080 is open on worker & cluster SGs, and pods are `Ready`.
- **No nodes registered**: ensure `aws-auth` includes the NodeInstanceRole ARN:
  ```bash
  kubectl -n kube-system get configmap aws-auth -o yaml
  ```

## Cleanup

```bash
make app-destroy
make destroy
```

## Repo layout

```
infra/
  cloudformation/eks-mini.json
  scripts/{deploy.sh,destroy.sh,lockdown-api.sh}
k8s/
  namespaces/demo.yaml
  apps/hello/{deployment.yaml,service-nlb.yaml}
.github/
  workflows/validate.yml
docs/
  operations.md
  troubleshooting.md
Makefile
