apiVersion: apps/v1
kind: Deployment
metadata:
  name: whisper-gradio-deployment
  namespace: whisper-neuron
spec:
  replicas: 1
  selector:
    matchLabels:
      app: whisper-gradio
  template:
    metadata:
      labels:
        app: whisper-gradio
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      automountServiceAccountToken: false
      containers:
      - name: whisper-gradio
        image: public.ecr.aws/v2f5y6u4/whisper-neuron/gradio:latest@sha256:3306e1797419278eadbf598540e55f20c371785076e3133b9b6e8ceff68780ec
        imagePullPolicy: Always
        securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - NET_RAW
            seccompProfile:
              type: RuntimeDefault
        env:
        - name: API_ENDPOINT
          value: "http://whisper-inference-service"
        - name: PORT
          value: "7860"
        ports:
        - containerPort: 7860
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
---
# Service to access the Gradio UI
apiVersion: v1
kind: Service
metadata:
  name: whisper-gradio-service
  namespace: whisper-neuron
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "${tags_csv}"
spec:
  selector:
    app: whisper-gradio
  type: LoadBalancer
  loadBalancerClass: eks.amazonaws.com/nlb
  ports:
  - protocol: TCP
    port: 80
    targetPort: 7860
