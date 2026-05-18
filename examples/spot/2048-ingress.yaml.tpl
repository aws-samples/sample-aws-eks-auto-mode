---
apiVersion: v1
kind: Service
metadata:
  namespace: game-2048-spot
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
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
  namespace: game-2048-spot
  name: params
spec:
  scheme: internet-facing
  tags:
${tags_yaml}

---
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  namespace: game-2048-spot
  labels:
    app.kubernetes.io/name: LoadBalancerController
  name: alb
spec:
  controller: eks.amazonaws.com/alb
  parameters:
    apiGroup: eks.amazonaws.com
    kind: IngressClassParams
    name: params

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: game-2048-spot
  name: ingress-2048
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-2048
                port:
                  number: 80
