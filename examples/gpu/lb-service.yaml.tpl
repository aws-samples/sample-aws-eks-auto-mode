---
apiVersion: v1
kind: Service
metadata:
  name: open-webui-service
  namespace: vllm-inference
spec:
  type: ClusterIP
  selector:
    app: open-webui-server
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: vllm-inference
  name: open-webui-ingress
%{ if enable_domain ~}
  annotations:
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    external-dns.alpha.kubernetes.io/hostname: gpu.${domain}
%{ endif ~}
spec:
  ingressClassName: alb
  rules:
%{ if enable_domain ~}
    - host: gpu.${domain}
      http:
%{ else ~}
    - http:
%{ endif ~}
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: open-webui-service
                port:
                  number: 80
