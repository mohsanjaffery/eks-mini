#!/usr/bin/env bash
set -euo pipefail
REGION="${REGION:-eu-west-1}"
STACK="${STACK:-eks-mini-stack}"
TEMPLATE="${TEMPLATE:-infra/cloudformation/eks-fixed-arm.json}"
CLUSTER="${CLUSTER:-eks-mini-cluster}"
rain deploy "$TEMPLATE" "$STACK" -r "$REGION" -y \
  --params ClusterName=$CLUSTER,KubernetesVersion=1.30,NodeInstanceType=t4g.micro,DesiredSize=2,MinSize=1,MaxSize=2,NodeVolumeSizeGiB=20,PublicAccessCidrs=0.0.0.0/0
