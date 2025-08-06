```bash
cd ../examples/o11y/kubecost

kubectl apply -f storage-class.yaml

aws ecr-public get-login-password \
  --region us-east-1 | helm registry login \
  --username AWS \
  --password-stdin public.ecr.aws

helm upgrade --install kubecost oci://public.ecr.aws/kubecost/cost-analyzer \
  --version 2.8.0 \
  --namespace kubecost --create-namespace \
  --values https://raw.githubusercontent.com/kubecost/cost-analyzer-helm-chart/v2.8.0/cost-analyzer/values-eks-cost-monitoring.yaml \
  --values values.yaml \
  --wait

```