#!/usr/bin/env bash
set -euo pipefail
REGION="${REGION:-eu-west-1}"
STACK="${STACK:-eks-mini-stack}"
aws cloudformation delete-stack --stack-name "$STACK" --region "$REGION"
aws cloudformation wait stack-delete-complete --stack-name "$STACK" --region "$REGION"
