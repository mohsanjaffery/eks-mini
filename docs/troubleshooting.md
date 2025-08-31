# Troubleshooting

## Nodes won't join (no `kubectl get nodes`)
- Check aws-auth ConfigMap contains your node role ARN.

## NLB target unhealthy
- Ensure the Service has endpoints and NodePort 31080 is reachable on all worker SGs and the cluster SG.

## Pending pods: "Too many pods"
- Micro instances have tiny max-pods.
  - Reduce CoreDNS to 1 replica; or
  - Add a second micro node or use a larger instance type.
