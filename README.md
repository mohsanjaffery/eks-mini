# eks-mini — Minimal EKS (free-tier friendly)

Spin up a tiny, low-cost **Amazon EKS** cluster with a sample **React SPA** served by NGINX and exposed via an **internet-facing NLB**.

**What you get**
- **VPC** with two public subnets (tagged for Kubernetes LoadBalancers)
- **EKS** cluster (v1.30) with managed add-ons: VPC CNI, CoreDNS, kube-proxy
- **Managed node group** on ARM (`t4g.micro`, AMI type `AL2023_ARM_64_STANDARD`)
- **Sample app:** React SPA (no build step) + NGINX, exposed via NLB (instance targets)
- **Fixed NodePort `31080`** to keep SG rules stable

> Cost note: EKS control plane + NLB have hourly costs. Nodes are micro to minimize spend; there are **no NAT Gateways**.

---

## Prereqs (macOS)

```bash
brew install awscli kubectl jq rain
# optional:
brew install gh pre-commit
```

AWS credentials with permissions for CloudFormation, EKS, ELBv2, EC2, and `iam:PassRole`/`iam:CreateServiceLinkedRole`.

---

## Quick start

```bash
# Variables (these match the Makefile defaults)
export REGION=eu-west-1
export STACK=eks-mini
export CLUSTER=eks-mini-cluster
export TEMPLATE=infra/cloudformation/eks-mini.json

# 1) Deploy infra (Rain). PublicAccessCidrs wide open for creation; lock down later.
rain deploy "$TEMPLATE" "$STACK" -r "$REGION" -y \
  --params ClusterName=$CLUSTER,KubernetesVersion=1.30,NodeInstanceType=t4g.micro,DesiredSize=2,MinSize=1,MaxSize=2,NodeVolumeSizeGiB=20,PublicAccessCidrs=0.0.0.0/0

# (Outputs include suggested next steps)
aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query 'Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}' -o table

# 2) Kubeconfig
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"
kubectl get nodes -o wide

# 3) Deploy the app (React SPA + NGINX + NLB)
make app-apply
```

### Open NodePort 31080 on security groups (once)
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

### Get the URL (DNS may take a minute to publish)
```bash
# wait for EXTERNAL-IP (hostname) then open or curl
make app-wait
make app-open      # or:
make app-curl
```

---

## Make targets

```text
validate     - JSON + CFN validate the template
deploy       - rain deploy (in-place updates supported)
destroy      - rain rm (delete stack)
kubeconfig   - configure kubectl for the cluster

app-apply    - deploy demo namespace, SPA deployment, and NLB Service
app-destroy  - delete the demo namespace
lockdown     - restrict API endpoint (private on, public to your IP)

api-auth     - curl EKS /version with IAM auth + cluster CA
app-url      - print app URL (NLB DNS)
app-curl     - HEAD request to app URL
app-open     - open app URL (macOS)
app-wait     - wait for Service EXTERNAL-IP then print URL
```

---

## App details (SPA)

- Config: `k8s/apps/hello/deployment.yaml`  
  - **ConfigMap** (`hello-spa`) serves `index.html` (React from CDN).
  - **InitContainer** writes pod metadata (name, namespace, node, pod IP, labels, annotations) into `/usr/share/nginx/html/podinfo`.
  - **Deployment** mounts the page and metadata into NGINX.
- Service: `k8s/apps/hello/service-nlb.yaml` → **internet-facing NLB**, fixed `nodePort: 31080`.

---

## Lock down the API endpoint

After the nodes join and you’ve verified access:
```bash
MYIP=$(curl -s https://checkip.amazonaws.com)/32
aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs="[$MYIP]"
```

You can also test the control-plane auth:
```bash
make api-auth
```

---

## Troubleshooting

- **NLB hostname doesn’t resolve immediately** (`curl: Could not resolve host`):  
  DNS may lag right after Service creation. Use `make app-wait` (and `make app-dns` if present).
- **NLB targets unhealthy:**  
  Ensure NodePort **31080** is open on all **worker SGs** and the **cluster SG**, and that the pod is `Ready`.
- **Pods Pending / “Too many pods”:**  
  Micro nodes have small max-pods. Scale CoreDNS to 1 or run 2 nodes.
- **403 on cluster endpoint:**  
  That’s the EKS API. Use `make api-auth` or `kubectl` after `aws eks update-kubeconfig`.

---

## Cleanup

```bash
make app-destroy
make destroy     # rain rm
```

---

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
  architecture.md
Makefile
```
