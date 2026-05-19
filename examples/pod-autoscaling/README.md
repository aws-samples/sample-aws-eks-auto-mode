# Pod Autoscaling on EKS Auto Mode

## Table of Contents
- [Overview](#overview)
- [Part 1: Horizontal Pod Autoscaler (HPA)](#part-1-horizontal-pod-autoscaler-hpa)
  - [HPA Architecture](#hpa-architecture)
  - [HPA Implementation Steps](#hpa-implementation-steps)
  - [HPA Cleanup](#hpa-cleanup)
- [Part 2: KEDA Event-Driven Autoscaling](#part-2-keda-event-driven-autoscaling)
- [Troubleshooting](#troubleshooting)

## Overview
Pod autoscaling is essential for maintaining optimal performance and cost efficiency in Kubernetes clusters. This example demonstrates two complementary approaches:

📊 **Horizontal Pod Autoscaler (HPA)**
- CPU and memory-based scaling
- Built-in Kubernetes functionality
- Ideal for traditional web applications

🎯 **KEDA (Kubernetes Event-Driven Autoscaling)**
- Event-driven scaling based on external metrics
- Supports 60+ scalers (SQS, Kafka, Redis, etc.)
- Perfect for event-driven and batch workloads

⚡ **Key Benefits**
- Automatic scaling based on demand
- Cost optimization through right-sizing
- Improved application performance and availability

## Part 1: Horizontal Pod Autoscaler (HPA)

### HPA Architecture
The HPA automatically scales the number of pods in a deployment based on observed CPU utilization, memory usage, or custom metrics.

**How it works**:
1. 📈 **Metrics Collection**: Metrics Server collects resource usage from pods
2. 🔍 **Evaluation**: HPA controller evaluates metrics against target thresholds
3. ⚖️ **Scaling Decision**: Calculates desired replica count based on current vs target metrics
4. 🔄 **Pod Adjustment**: Updates deployment replica count to match demand

**Key Components**:
- **Metrics Server**: Collects resource metrics from kubelets
- **HPA Controller**: Makes scaling decisions based on metrics
- **Target Deployment**: The workload being scaled
- **Load Generator**: Simulates traffic to trigger scaling

### HPA Implementation Steps

#### 1. Setup EKS Auto Mode Cluster
First, deploy your EKS cluster using Terraform:

```bash
cd sample-aws-eks-auto-mode/terraform

terraform init
terraform apply -auto-approve

$(terraform output -raw configure_kubectl)
```

#### 2. Install Metrics Server
The HPA requires the Metrics Server to collect resource metrics from pods:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

> 📘 **Note**: The Metrics Server collects resource metrics from kubelets and exposes them through the Kubernetes API. It may take a minute or two to become ready.

Verify the Metrics Server is running:
```bash
kubectl get pods -n kube-system | grep metrics-server
```

#### 3. Deploy the Sample Application
Deploy a PHP Apache server that will serve as our scaling target:

```bash
cd ../examples/pod-autoscaling/hpa

kubectl apply -f php-apache.yaml
```

> ✅ **Application Details**: The php-apache deployment includes:
> - **CPU Request**: 200m (200 millicores)
> - **CPU Limit**: 500m (500 millicores)
> - **Container**: `registry.k8s.io/hpa-example` - a simple PHP server
> - **Service**: Exposes the application on port 80

#### 4. Create the HorizontalPodAutoscaler
Create an HPA that maintains between 1 and 10 replicas based on CPU utilization:

```bash
kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10
```

Alternatively, you can use the declarative approach:

```bash
kubectl apply -f hpa.yaml
```

#### 5. Verify HPA Status
Check the current status of the HPA:

```bash
kubectl get hpa
```

Expected output:
```
NAME         REFERENCE                     TARGET    MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache/scale   0% / 50%  1         10        1          18s
```

> 📘 **Note**: The current CPU consumption shows 0% because there's no load on the server yet.

#### 6. Generate Load to Trigger Scaling
Start a load generator to increase CPU utilization:

```bash
# Run this in a separate terminal
kubectl run -i --tty load-generator --rm --image=busybox:1.28 --restart=Never -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://php-apache; done"
```

#### 7. Watch the Scaling in Action
In another terminal, monitor the HPA scaling behavior:

```bash
# Press Ctrl+C to stop watching when ready
kubectl get hpa php-apache --watch
```

Within a minute, you should see increased CPU load:
```
NAME         REFERENCE                     TARGET      MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache/scale   305% / 50%  1         10        1          3m
```

Then observe the replica count increase (will stabilize between 6-8):
```
NAME         REFERENCE                     TARGET      MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache/scale   305% / 50%  1         10        8          3m
```

Verify the deployment scaling:
```bash
kubectl get deployment php-apache
```

Expected output:
```
NAME         READY   UP-TO-DATE   AVAILABLE   AGE
php-apache   8/8     8            8           19m
```

#### 8. Stop Load Generation and Observe Scale-Down
Stop the load generator by pressing `Ctrl+C` in the load generator terminal.

Monitor the scale-down process:
```bash
kubectl get hpa php-apache --watch
```

After a few minutes, you'll see the CPU utilization drop and replicas scale back down:
```
NAME         REFERENCE                     TARGET       MINPODS   MAXPODS   REPLICAS   AGE
php-apache   Deployment/php-apache/scale   0% / 50%     1         10        1          11m
```

> ⏱️ **Scaling Timing**: 
> - **Scale-up**: Typically occurs within 1-2 minutes of increased load
> - **Scale-down**: Takes 5-10 minutes to ensure stability before reducing replicas

### HPA Cleanup

Remove the HPA resources:

```bash
kubectl delete pod load-generator

# Remove the HPA
kubectl delete hpa php-apache

# Remove the application
kubectl delete -f php-apache.yaml
```

> 📚 **Attribution**: This HPA demo was adapted from the [Kubernetes HorizontalPodAutoscaler Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/).

## Part 2: KEDA Event-Driven Autoscaling

### KEDA Architecture
[KEDA (Kubernetes Event-Driven Autoscaling)](https://keda.sh/) extends Kubernetes with event-driven autoscaling capabilities beyond traditional CPU/memory metrics. Key benefits include:

🎯 **Event-Driven Scaling**
- Scale based on external metrics (SQS queue depth, Kafka lag, etc.)
- Support for 60+ scalers including AWS services
- Zero-to-N and N-to-zero scaling capabilities

🚀 **Advanced Capabilities**
- Custom metrics from external systems
- Integration with Horizontal Pod Autoscaler
- Seamless integration with Karpenter for node-level scaling

⚡ **Perfect for Modern Workloads**
- Batch processing jobs
- Event-driven microservices
- AI/ML inference workloads
- Queue-based processing systems

This example demonstrates KEDA scaling a GPU-based AI model inference workload based on Amazon SQS queue depth.

**How it works**:
1. 📨 **Message Queue**: SQS receives inference requests
2. 📊 **KEDA Monitoring**: ScaledObject monitors queue depth
3. 🔄 **Scaling Decision**: KEDA scales pods based on queue metrics
4. 🤖 **GPU Processing**: Scaled pods process inference requests
5. 📉 **Scale Down**: Pods scale to zero when queue is empty

**Key Components**:
- **KEDA Controller**: Manages event-driven scaling
- **ScaledObject**: Defines scaling behavior and triggers
- **SQS Queue**: Message queue for inference requests
- **GPU Inference Pods**: AI model serving containers
- **Karpenter Integration**: Automatic node provisioning for GPU workloads

### KEDA Implementation Steps

> ⚠️ **Prerequisites**: 
> - **GPU Instance Availability**: Ensure you have sufficient GPU quota for your AWS account
> - **Helm**: Required for KEDA installation

#### 1. Setup AWS Infrastructure
Deploy the required AWS resources (SQS queue, IAM roles) using Terraform:

```bash
# Navigate to KEDA terraform directory (assuming you're in HPA folder)
cd ../keda/terraform

# Initialize and deploy AWS resources
terraform init
terraform apply -auto-approve
```

> 📦 **AWS Resources Created**:
> - **SQS Queue**: For inference request messages
> - **IAM Roles**: Service accounts for KEDA and SQS access
> - **IAM Policies**: Permissions for queue operations

#### 2. Configure Kubernetes Resources
Set up the necessary namespaces and service accounts:

```bash
# Navigate back to KEDA directory
cd ..

# Create namespaces and service accounts
kubectl apply -f namespace.yaml
kubectl apply -f keda-service-account.yaml
kubectl apply -f vllm-qwen3/namespace.yaml
kubectl apply -f sqs-reader-service-account.yaml
```

> ✅ **Service Account Details**: 
> - **KEDA Service Account**: Allows KEDA to read SQS metrics
> - **SQS Reader Service Account**: Enables pods to consume SQS messages
> - **IAM Role Annotations**: Links Kubernetes service accounts to AWS IAM roles

#### 3. Install KEDA with Helm
Deploy KEDA controller with custom configuration:

```bash
# Add KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install KEDA with custom values
helm install keda kedacore/keda \
  --namespace keda \
  --version 2.17.0 \
  --values keda-helm-values.yaml
```

Verify KEDA installation:
```bash
kubectl get pods -n keda
```

Expected output:
```
NAME                                      READY   STATUS    RESTARTS   AGE
keda-admission-webhooks-xxx               1/1     Running   0          2m
keda-operator-xxx                         1/1     Running   0          2m
keda-operator-metrics-apiserver-xxx       1/1     Running   0          2m
```

> 📘 **KEDA Components**:
> - **Operator**: Main KEDA controller managing ScaledObjects
> - **Metrics API Server**: Exposes custom metrics to HPA
> - **Admission Webhooks**: Validates KEDA resource configurations

#### 4. Deploy GPU NodePool
Ensure GPU nodes are available for the AI workload:

```bash
# Deploy GPU-enabled NodePool
kubectl apply -f ../../../nodepools/gpu-nodepool.yaml
```

> ⚠️ **GPU Node Configuration**: The NodePool includes:
> - **Instance Types**: G5, G6, or G6e instances optimized for ML workloads
> - **Taints**: `nvidia.com/gpu=true:NoSchedule` to ensure only GPU workloads are scheduled
> - **Labels**: Proper GPU node identification for workload placement

#### 5. Deploy AI Model with SQS Consumer
Deploy the GPU-based inference workload that will be scaled by KEDA:

```bash
kubectl apply -f vllm-qwen3/model-qwen3-4b-fp8-with-sqs.yaml
```

> 🤖 **Model Details**:
> - **Model**: Qwen3-4B-FP8 optimized for GPU inference
> - **SQS Integration**: Built-in consumer for processing queue messages
> - **GPU Tolerations**: Configured to run on GPU-tainted nodes
> - **Resource Requests**: Optimized for efficient GPU utilization

Verify the deployment:
```bash
kubectl get pods -n vllm
kubectl get deployments -n vllm
```

Initially, you should see 0 replicas since there are no messages in the queue.

#### 6. Deploy KEDA ScaledObject
Create the ScaledObject that defines the scaling behavior:

```bash
kubectl apply -f scaledObject.yaml
```

> 📊 **Scaling Configuration**:
> - **Trigger**: SQS queue depth
> - **Target**: 5 messages per pod
> - **Min Replicas**: 0 (scale to zero when idle)
> - **Max Replicas**: 10 (adjust based on your needs)
> - **Cooldown**: Prevents rapid scaling oscillations

Verify the ScaledObject:
```bash
kubectl get scaledobject -n vllm
```

Expected output:
```
NAME                        SCALETARGETKIND      SCALETARGETNAME      MIN   MAX   READY   ACTIVE   FALLBACK   PAUSED    TRIGGERS        AUTHENTICATIONS   AGE
model-qwen3-4b-fp8-scaler   apps/v1.Deployment   model-qwen3-4b-fp8   0     10    True    False    Unknown    Unknown   aws-sqs-queue                     6s
```

#### 7. Test the Scaling Behavior
Generate test messages to trigger scaling:

```bash
# Deploy job that generates 50 inference requests
kubectl apply -f prompt-generator-job.yaml
```

> 🧪 **Test Scenario**: The prompt generator creates 50 sample inference requests in the SQS queue, simulating real-world load.

#### 8. Monitor the Scaling Process
Watch the scaling behavior in real-time:

1. **Check SQS Queue Depth**:
Wait for job to finish sending messages first. 

```bash
cd terraform
QUEUE_URL=$(terraform output -raw sqs_url)
aws sqs get-queue-attributes \
  --queue-url $QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages
```

2. **Monitor ScaledObject Status**:
```bash
kubectl describe scaledobject model-qwen3-4b-fp8-scaler -n vllm
```

3. **Watch Deployment Scaling**:
```bash
kubectl get deployment model-qwen3-4b-fp8 -n vllm --watch
```

4. **Monitor Pod Creation**:
```bash
kubectl get pods -n vllm --watch
```

> ⏱️ **Expected Timeline**:
> - **0-1 min**: Messages appear in SQS queue (50 messages)
> - **1-2 min**: KEDA detects queue depth and triggers scaling
> - **2-5 min**: GPU nodes provision and pods start (model download begins)
> - **5-6 min**: Pods become ready and start consuming messages
> - **6-7 min**: All messages processed, queue becomes empty
> - **7-8 min**: Pods scale down to zero after cooldown period

#### 9. Observe the Processing
Monitor the actual inference processing:

1. **Check Pod Logs** (model initialization):
```bash
kubectl logs -n vllm deployment/model-qwen3-4b-fp8 -f
```

2. **Monitor Message Processing**:
```bash
# Watch queue depth decrease as messages are processed
watch "aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names ApproximateNumberOfMessages"
```

> 🎯 **Success Indicators**:
> - Queue depth increases to 50, then decreases to 0
> - Deployment scales from 0 to multiple replicas, then back to 0
> - Pod logs show model loading and inference processing
> - Processing completes within expected timeframe

### KEDA Cleanup

🧹 Follow these steps to clean up all KEDA resources:

#### 1. Remove Application Resources
```bash
# Remove test job and scaling resources
kubectl delete job prompt-generator -n keda --ignore-not-found
kubectl delete -f scaledObject.yaml --ignore-not-found
kubectl delete -f vllm-qwen3/model-qwen3-4b-fp8-with-sqs.yaml --ignore-not-found
```

#### 2. Uninstall KEDA
```bash
# Remove KEDA Helm installation
helm uninstall keda -n keda
```

#### 3. Remove Kubernetes Resources
```bash
# Clean up service accounts and namespaces
kubectl delete -f sqs-reader-service-account.yaml --ignore-not-found
kubectl delete -f keda-service-account.yaml --ignore-not-found
kubectl delete namespace keda --ignore-not-found
kubectl delete namespace vllm --ignore-not-found
```

#### 4. Destroy AWS Infrastructure
```bash
# Remove AWS resources (SQS, IAM roles)
cd terraform
terraform destroy -auto-approve
```

> ⚠️ **Warning**: This will remove all AWS resources created for the KEDA demo, including the SQS queue and IAM roles.
