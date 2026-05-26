---
sidebar_position: 4
title: Neuron Workloads on EKS Auto Mode
---

# Neuron Workloads on EKS Auto Mode

## Table of Contents
- [Prerequisites](#prerequisites)
- [Overview](#overview)
- [Architecture](#architecture)
- [Implementation Steps](#implementation-steps)
- [Clean up](#clean-up)
- [Troubleshooting](#troubleshooting)

## Prerequisites

Cluster deployed and `kubectl` configured per [Quick Start](../../README.md#quick-start).

## Overview
[AWS Inferentia2](https://aws.amazon.com/machine-learning/inferentia/) accelerates machine learning inference workloads with custom-built chips. Key benefits include:

🚀 **High Performance Inference**
- Purpose-built ML acceleration
- Optimized for transformer models
- Cost-effective alternative to GPUs

🎯 **ML Model Support**
- Supports popular ML frameworks
- Optimized for transformer architectures
- OpenAI-compatible serving via [vLLM](https://docs.vllm.ai/)

This example demonstrates deploying [DeepSeek-R1-0528-Qwen3-8B](https://huggingface.co/deepseek-ai/DeepSeek-R1-0528-Qwen3-8B) on EKS Auto Mode using vLLM on Inferentia2. The container image ships a pre-compiled Neuron artifact, so no separate compile job is needed.

The manifest is adapted from [aws-samples/sample-genai-on-eks-starter-kit](https://github.com/aws-samples/sample-genai-on-eks-starter-kit/blob/main/components/llm-model/vllm/model-deepseek-r1-qwen3-8b-neuron.template.yaml).

## Architecture
This example showcases Inferentia2-accelerated workloads using the following components:

### 🖥️ Instance Types
- **Default**: inf2 instances (optimized for ML inference)
- **Customization**: Available in [neuron-nodepool.yaml.tpl](../../nodepool-templates/neuron-nodepool.yaml.tpl)

### 🔧 Key Components
📦 **Infrastructure**
- NodePool and NodeClass for Neuron workload management
- Application Load Balancer (Ingress) for HTTP access — internal-scheme by default, opt-in `internet-facing` + HTTPS via `var.base_domain`

🧠 **ML Components**
- vLLM serving DeepSeek-R1-Qwen3-8B on 2 Neuron cores (`tensor-parallel-size=2`)
- OpenAI-compatible chat completions endpoint
- DeepSeek-R1 reasoning parser enabled

## Implementation Steps

### 1. Deploy Neuron NodePool
Deploy the NodePool that will manage our Inferentia2 instances:

```bash
kubectl apply -f ../../nodepools/neuron-nodepool.yaml
```

> ⚠️ The Neuron NodePool applies the following taint to ensure only Neuron-compatible workloads are scheduled on these nodes:
>
> ```yaml
> taints:
>   - key: "aws.amazon.com/neuron"
>     value: "true"
>     effect: "NoSchedule"   # Prevents non-Neuron pods from scheduling
> ```
>
> Any pods that need to run on Neuron nodes must include matching tolerations in their specifications.

### 2. Deploy the vLLM Model

```bash
kubectl apply -f vllm-deployment.yaml
```

> ✅ The Deployment includes the toleration and `aws.amazon.com/neuroncore: 2` resource request that drive scheduling onto a Neuron node:
>
> ```yaml
> tolerations:
>   - key: aws.amazon.com/neuron
>     operator: Exists
>     effect: NoSchedule
> resources:
>   requests:
>     aws.amazon.com/neuroncore: 2
>   limits:
>     aws.amazon.com/neuroncore: 2
> ```

Wait for the pod to schedule onto a Neuron node and report `Running`:

```bash
kubectl -n vllm-neuron get pods -w
```

Once the pod is `Running`, vLLM still needs a minute or two to load the model. Tail the logs and wait for `Application startup complete`:

```bash
kubectl -n vllm-neuron logs -f deployment/deepseek-r1-qwen3-8b-neuron
```

> 📘 The manifest provisions a `ClusterIP` Service `deepseek-r1-qwen3-8b-neuron` (port 80 → 8000) and an Ingress `deepseek-r1-qwen3-8b-neuron` using the cluster-wide `alb` IngressClass. By default the ALB scheme is `internal` (VPC-only) — no public endpoint is created.

### 3. Test the Endpoint

By default, this example exposes its API via an **internal ALB** — reachable from inside the VPC only. To call it from your laptop, port-forward the Service:

```bash
kubectl -n vllm-neuron port-forward svc/deepseek-r1-qwen3-8b-neuron 8000:80
```

Then hit the OpenAI-compatible chat completions endpoint:

```bash
curl http://localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"deepseek-r1-qwen3-8b-neuron","messages":[{"role":"user","content":"Why is the sky blue?"}]}'
```

If you want to inspect the ALB DNS name directly (e.g. from a bastion or VPN):

```bash
kubectl get ingress deepseek-r1-qwen3-8b-neuron -n vllm-neuron \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

To expose the API publicly over HTTPS, deploy the Terraform stack with `var.base_domain` set to a public Route53 zone you own (see top-level [README](../../README.md#-public-exposure-opt-in)). The example will be reachable at `https://neuron.<full_domain>` once external-dns publishes the record.

## Clean up

```bash
kubectl delete -f vllm-deployment.yaml
kubectl delete -f ../../nodepools/neuron-nodepool.yaml
```

## Troubleshooting

🔧 Common issues and their solutions:

### 🎯 Pod Scheduling Issues
1. **Pod stuck in `Pending`**
   - Check scheduling events:
     ```bash
     kubectl -n vllm-neuron describe pod -l app=deepseek-r1-qwen3-8b-neuron
     ```
   - Confirm a Neuron node was provisioned by the NodePool:
     ```bash
     kubectl get nodes -l karpenter.sh/nodepool=neuron
     ```

2. **Insufficient Neuron capacity**
   - Ensure sufficient inf2 quota in your AWS account
   - Check pod scheduling events:
     ```bash
     kubectl -n vllm-neuron get events --sort-by=.lastTimestamp
     ```

### 🧠 Model Serving Issues
1. **Pod logs**
   - Tail vLLM startup and request logs:
     ```bash
     kubectl -n vllm-neuron logs -f deployment/deepseek-r1-qwen3-8b-neuron
     ```

2. **Neuron runtime status**
   - Inspect Neuron devices on the pod:
     ```bash
     kubectl -n vllm-neuron exec -it deployment/deepseek-r1-qwen3-8b-neuron -- neuron-ls
     ```

### 🔄 Load Balancer Issues
1. **Ingress / ALB Status**
   - Check Ingress provisioning:
     ```bash
     kubectl -n vllm-neuron describe ingress deepseek-r1-qwen3-8b-neuron
     ```
   - Check ALB controller logs:
     ```bash
     kubectl -n kube-system logs deployment/aws-load-balancer-controller
     ```
   - Verify the ALB hostname resolves and target group health is green

> 💡 **Tip**: Always check pod logs and events first when troubleshooting deployment issues.
