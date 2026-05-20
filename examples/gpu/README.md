# GPU Workloads on EKS Auto Mode

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Implementation Steps](#implementation-steps)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

## Overview
[NVIDIA GPUs on Amazon EC2](https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing) supercharge your workloads with powerful GPU acceleration. Key benefits include:

🚀 **High Performance Computing**
- GPU accelerators from g3, g4, g5, g6, p3, and p4 families
- Optimized for machine learning and graphics workloads
- Ideal for running large language models

🤖 **AI/ML Capabilities**
- Perfect for GenAI model deployment
- Supports complex deep learning tasks
- Accelerated model inference

⚙️ **Flexible Configuration**
- Customizable instance types
- Scalable GPU resources
- EKS Auto Mode integration

This example demonstrates deploying a GenAI model ([Qwen 3 32b fp8](https://huggingface.co/Qwen/Qwen3-32B-FP8)) on EKS Auto Mode.

> ⚠️ **Prerequisites**: 
> - You must have a Hugging Face account with an access token!
> - **GPU Instance Availability**: Many AWS accounts have a default service quota of 0 for p* and g* GPU instance types. You may need to request a quota increase through the AWS Service Quotas console before deploying GPU workloads. This process can take 24-48 hours for approval.

## Architecture
This example showcases GPU-accelerated workloads on EKS Auto Mode using the following components:

### 🖥️ Instance Types
- **Default**: G5, G6 or G6e instances (optimized for ML workloads)
- **Customization**: Available in [gpu-nodepool.yaml.tpl](../../nodepool-templates/gpu-nodepool.yaml.tpl)

### 🔧 Key Components
📦 **Infrastructure**
- NodePool and NodeClass for GPU workload management
- Application Load Balancer (Ingress) for HTTP access — internal-scheme by default, opt-in `internet-facing` + HTTPS via `var.base_domain`

🧠 **AI Components**
- Hugging Face model deployment ([Qwen 3 32b fp8](https://huggingface.co/Qwen/Qwen3-32B-FP8))
- Interactive Web UI for model interaction

## Implementation Steps

### 1. Get Hugging Face Access Token
Create a Hugging Face account and generate a FINEGRAINED [Access Token](https://huggingface.co/settings/tokens)

### 2. Setup EKS Auto Mode Cluster
Deploy the cluster using Terraform:
```bash
cd sample-aws-eks-auto-mode/terraform
terraform init
terraform apply -auto-approve
$(terraform output -raw configure_kubectl)
```

### 3. Deploy GPU NodePool
Deploy the NodePool that will manage our GPU instances:

```bash
cd ../nodepools
kubectl apply -f gpu-nodepool.yaml
```

> ⚠️ The GPU NodePool applies the following taint to ensure only GPU-compatible workloads are scheduled on these nodes:
>
> ```yaml
> taints:
>   - key: "nvidia.com/gpu"
>     value: "true"
>     effect: "NoSchedule"   # Prevents non-GPU pods from scheduling
> ```
>
> Any pods that need to run on GPU nodes must include matching tolerations in their specifications.

### 4. Configure Namespace and Secrets

1. **Create Namespace**:
```bash
cd ../examples/gpu
kubectl apply -f namespace.yaml
```

2. **Add Hugging Face Token**:
```bash
# Replace <your_actual_hugging_face_token> with your token
kubectl create secret generic hf-secret \
  -n vllm-inference \
  --from-literal=hf_api_token=<your_actual_hugging_face_token>
```

### 5. Deploy Model and UI

1. **Deploy the Model**:
Following command will deploy Qwen3 32b (fp8). We also have another manifest file that allows you to deploy [Deepseek](vllm-deepseek-gpu.yaml) instead.

```bash
kubectl apply -f model-qwen3-32b-fp8.yaml
```

> ✅ The model deployment includes the required toleration to run on GPU nodes:
>
> ```yaml
> tolerations:
>   - key: "nvidia.com/gpu"     # Matches the GPU node taint
>     value: "true"
>     effect: "NoSchedule"      # Allows scheduling on tainted nodes
> ```
>
> This toleration enables the pods to be scheduled on our GPU-enabled instances.

2. **Deploy the Web UI**:
```bash
kubectl apply -f open-webui.yaml
```

### 6. Deploy the Service and Ingress
Apply the ClusterIP Service + ALB Ingress that front the Web UI:

```bash
kubectl apply -f lb-service.yaml
```

> 📘 The manifest provisions a `ClusterIP` Service `open-webui-service` (port 80 → 8080) and an Ingress `open-webui-ingress` using the cluster-wide `alb` IngressClass. By default the ALB scheme is `internal` (VPC-only) — no public endpoint is created.

### 7. Access the Application

By default, this example exposes its UI via an **internal ALB** — reachable from inside the VPC only. To access it from your laptop, use `kubectl port-forward`:

```bash
kubectl port-forward -n vllm-inference svc/open-webui-service 8080:80
# then open http://localhost:8080
```

If you want to inspect the ALB DNS name directly (e.g. from a bastion or VPN):

```bash
kubectl get ingress open-webui-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
  -n vllm-inference
```

To expose the UI publicly over HTTPS, deploy the Terraform stack with `var.base_domain` set to a public Route53 zone you own (see top-level [README](../../README.md#-public-exposure-opt-in)). The example will be reachable at `https://gpu.<full_domain>` once external-dns publishes the record.

> ⚠️ **Select a Model**: If you are unable to select a model, it means the model is still being downloaded and is not yet being served by our inferencing server pod. Just refresh until you see a model available.


## Cleanup

🧹 Follow these steps to clean up all resources:

### 1. Remove Kubernetes Resources
First, remove the application components and node pool:

```bash
# Remove application components
kubectl delete -f lb-service.yaml
kubectl delete -f open-webui.yaml
kubectl delete -f model-qwen3-32b-fp8.yaml
kubectl delete -f namespace.yaml

# Remove GPU node pool
kubectl delete -f ../../nodepools/gpu-nodepool.yaml
```

### 2. Remove Cluster (Optional)
If you're done with the entire cluster:

```bash
# Navigate to Terraform directory
cd ../../terraform

# Initialize and destroy infrastructure
terraform init
terraform destroy --auto-approve
```

> ⚠️ **Warning**: This will delete the entire EKS cluster and all associated resources. Make sure you want to proceed.

> For a comprehensive teardown that also cleans up orphaned AWS resources (load balancers, volumes, ENIs, etc.), use `./scripts/cleanup.sh` from the repo root. See the [root README](../../README.md#cleanup) for details.

## Troubleshooting

🔧 Common issues and their solutions:

### 🎯 Model Deployment Issues
1. **GPU Node Provisioning**
   - Verify nodes are properly labeled for GPU
   - Check node status with `kubectl get nodes`
   - Ensure GPU drivers are initialized

2. **Model Initialization**
   - Check pod logs for startup errors:
     ```bash
     kubectl logs -n vllm-inference deployment/qwen3-32b-fp8
     ```
   - Verify Hugging Face token is valid

### 🔄 Load Balancer Issues
1. **Ingress / ALB Status**
   - Check Ingress provisioning:
     ```bash
     kubectl describe ingress open-webui-ingress -n vllm-inference
     ```
   - Check ALB controller logs:
     ```bash
     kubectl logs -n kube-system deployment/aws-load-balancer-controller
     ```
   - Verify the ALB hostname resolves and target group health is green

### 💻 Resource Constraints
1. **GPU Capacity**
   - Ensure sufficient GPU quota in your AWS account
   - Monitor GPU utilization:
     ```bash
     kubectl describe node <node-name>
     ```
   - Check for pod scheduling events:
     ```bash
     kubectl get events -n vllm-inference
     ```

> 💡 **Tip**: Always check pod logs and events first when troubleshooting deployment issues.
