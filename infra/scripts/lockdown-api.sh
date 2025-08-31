#!/usr/bin/env bash
set -euo pipefail
CLUSTER="${1:?cluster name}"
REGION="${2:?region}"
MYIP="$(curl -s https://checkip.amazonaws.com)/32"
aws eks update-cluster-config --name "$CLUSTER" --region "$REGION" \
  --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs="[$MYIP]"
