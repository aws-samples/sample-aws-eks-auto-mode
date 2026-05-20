---
apiVersion: v1
kind: Service
metadata:
  namespace: game-2048
  name: service-2048
spec:
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  type: NodePort
  selector:
    app.kubernetes.io/name: app-2048

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: game-2048
  name: ingress-2048
%{ if enable_domain ~}
  annotations:
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    external-dns.alpha.kubernetes.io/hostname: 2048-graviton.${domain}
%{ endif ~}
spec:
  ingressClassName: alb
  rules:
%{ if enable_domain ~}
    - host: 2048-graviton.${domain}
      http:
%{ else ~}
    - http:
%{ endif ~}
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-2048
                port:
                  number: 80
