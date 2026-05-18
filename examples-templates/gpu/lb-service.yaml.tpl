---
apiVersion: v1
kind: Service
metadata:
  name: open-webui-service
  namespace: vllm-inference
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "${tags_csv}"
spec:
  selector:
    app: open-webui-server
  type: LoadBalancer
  loadBalancerClass: eks.amazonaws.com/nlb
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
