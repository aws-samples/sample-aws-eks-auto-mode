---
apiVersion: v1
kind: Namespace
metadata:
  name: vllm-neuron
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deepseek-r1-qwen3-8b-neuron
  namespace: vllm-neuron
spec:
  replicas: 1
  selector:
    matchLabels:
      app: deepseek-r1-qwen3-8b-neuron
  template:
    metadata:
      labels:
        app: deepseek-r1-qwen3-8b-neuron
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      automountServiceAccountToken: false
      containers:
        - name: vllm
          image: public.ecr.aws/agentic-ai-platforms-on-k8s/vllm-neuron:deepseek-r1-qwen3-8b-optimum-neuron
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - NET_RAW
            seccompProfile:
              type: RuntimeDefault
          command: ["vllm", "serve"]
          args:
            - /root/.cache/neuron/deepseek-ai/DeepSeek-R1-0528-Qwen3-8B
            - --served-model-name=deepseek-r1-qwen3-8b-neuron
            - --trust-remote-code
            - --gpu-memory-utilization=0.90
            - --reasoning-parser=deepseek_r1
            - --tensor-parallel-size=2
            - --max-num-seqs=2
            - --max-model-len=8192
          env:
            - name: HF_HOME
              value: /root/.cache/huggingface
            - name: HF_HUB_CACHE
              value: /root/.cache/huggingface/hub
            - name: NEURON_RT_NUM_CORES
              value: "2"
            - name: NEURON_RT_VISIBLE_CORES
              value: "0-1"
          ports:
            - name: http
              containerPort: 8000
          resources:
            requests:
              cpu: 3
              memory: 12Gi
              aws.amazon.com/neuroncore: 2
            limits:
              aws.amazon.com/neuroncore: 2
      tolerations:
        - key: aws.amazon.com/neuron
          operator: Exists
          effect: NoSchedule
---
apiVersion: v1
kind: Service
metadata:
  name: deepseek-r1-qwen3-8b-neuron
  namespace: vllm-neuron
spec:
  type: ClusterIP
  selector:
    app: deepseek-r1-qwen3-8b-neuron
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: vllm-neuron
  name: deepseek-r1-qwen3-8b-neuron
%{ if enable_domain ~}
  annotations:
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    external-dns.alpha.kubernetes.io/hostname: neuron.${domain}
%{ endif ~}
spec:
  ingressClassName: alb
  rules:
%{ if enable_domain ~}
    - host: neuron.${domain}
      http:
%{ else ~}
    - http:
%{ endif ~}
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: deepseek-r1-qwen3-8b-neuron
                port:
                  number: 80
