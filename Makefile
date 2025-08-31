REGION ?= eu-west-1
STACK  ?= eks-mini
CLUSTER?= eks-mini-cluster
TEMPLATE ?= infra/cloudformation/eks-mini.json

.PHONY: help validate deploy destroy kubeconfig app-apply app-destroy lockdown api-auth app-url app-curl app-open app-wait

help:
	@echo "Targets: validate | deploy | destroy | kubeconfig | app-apply | app-destroy | lockdown | api-auth | app-url | app-curl | app-open | app-wait"

validate:
	jq empty $(TEMPLATE)
	aws cloudformation validate-template --region $(REGION) --template-body file://$(TEMPLATE)

deploy:
	rain deploy $(TEMPLATE) $(STACK) -r $(REGION) -y \
	  --params ClusterName=$(CLUSTER),KubernetesVersion=1.30,NodeInstanceType=t4g.micro,DesiredSize=2,MinSize=1,MaxSize=2,NodeVolumeSizeGiB=20,PublicAccessCidrs=0.0.0.0/0

destroy:
	aws cloudformation delete-stack --stack-name $(STACK) --region $(REGION)
	aws cloudformation wait stack-delete-complete --stack-name $(STACK) --region $(REGION)

kubeconfig:
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION)

app-apply:
	kubectl apply -f k8s/namespaces/demo.yaml
	kubectl -n demo apply -f k8s/apps/hello/deployment.yaml
	kubectl -n demo apply -f k8s/apps/hello/service-nlb.yaml

app-destroy:
	kubectl delete ns demo --ignore-not-found

lockdown:
	./infra/scripts/lockdown-api.sh $(CLUSTER) $(REGION)

# ---- New helpers ----

# Auth to the EKS API and show /version (HTTPS with cluster CA + IAM token)
api-auth:
	@set -euo pipefail; \
	ENDPOINT=$$(aws eks describe-cluster --name $(CLUSTER) --region $(REGION) --query 'cluster.endpoint' --output text); \
	aws eks describe-cluster --name $(CLUSTER) --region $(REGION) --query 'cluster.certificateAuthority.data' --output text | base64 --decode > /tmp/eks-$(CLUSTER).crt; \
	TOKEN=$$(aws eks get-token --cluster-name $(CLUSTER) --region $(REGION) --query 'status.token' --output text); \
	echo "Endpoint: $$ENDPOINT"; \
	echo "GET $$ENDPOINT/version"; \
	curl -sS --cacert /tmp/eks-$(CLUSTER).crt -H "Authorization: Bearer $$TOKEN" "$$ENDPOINT/version" || (echo "Tip: ensure your IP/CIDR is allowed or the private endpoint is reachable." && false)

# Print the app URL (NLB DNS) from Service demo/hello
app-url:
	@set -euo pipefail; \
	HOST=$$(kubectl -n demo get svc/hello --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true); \
	if [ -z "$$HOST" ]; then \
	  echo "Service demo/hello has no external hostname yet (still provisioning?)."; exit 1; \
	else \
	  echo "App URL: http://$$HOST"; \
	fi

# Curl the app URL (HEAD) for a quick 200/302/etc.
app-curl:
	@set -euo pipefail; \
	HOST=$$(kubectl -n demo get svc/hello --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'); \
	test -n "$$HOST"; \
	echo "curl -I http://$$HOST"; \
	curl -I "http://$$HOST"

# Open the app in your default browser (macOS)
app-open:
	@set -euo pipefail; \
	HOST=$$(kubectl -n demo get svc/hello --output jsonpath='{.status.loadBalancer.ingress[0].hostname}'); \
	test -n "$$HOST"; \
	open "http://$$HOST"

# Wait until the Service gets an external hostname, then print it
app-wait:
	@set -euo pipefail; \
	echo "Waiting for demo/hello EXTERNAL-IP..."; \
	for i in $$(seq 1 60); do \
	  HOST=$$(kubectl -n demo get svc/hello --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true); \
	  if [ -n "$$HOST" ]; then echo "App URL: http://$$HOST"; exit 0; fi; \
	  sleep 5; \
	done; \
	echo "Timed out waiting for EXTERNAL-IP on demo/hello"; exit 1
