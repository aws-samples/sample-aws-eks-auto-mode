---
sidebar_position: 2
title: Spot Workloads on EKS Auto Mode
description: "Run Spot instances on EKS Auto Mode — configure NodePools for Spot capacity, handle interruptions gracefully, and reduce Kubernetes compute costs by up to 90%."
keywords: [EKS Spot instances, eks auto mode spot, spot kubernetes, reduce EKS costs, spot nodepool]
---

# Spot Workloads on EKS Auto Mode

## Table of Contents
- [Overview](#overview)
- [Architecture](#architecture)
- [Implementation Steps](#implementation-steps)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

## Prerequisites

Cluster deployed and `kubectl` configured per [Quick Start](../../README.md#quick-start).

## Overview
[Amazon EC2 Spot Instances](https://aws.amazon.com/ec2/spot/) let you take advantage of unused EC2 capacity at steep discounts. Key benefits include:

💰 **Cost Optimization**
- Up to 90% cost savings compared to On-Demand instances
- Ideal for fault-tolerant, flexible workloads
- Pay only for what you use

⚡ **Scalability**
- Access to large-scale compute capacity
- Perfect for batch processing and stateless applications
- Automatic capacity rebalancing

🔄 **Flexibility**
- Mix of instance types and sizes
- Automatic instance selection based on availability
- Graceful interruption handling

## Architecture
This example demonstrates how to run workloads on Spot instances in EKS Auto Mode using Karpenter's spot instance management capabilities.

**Key Components**:
📄 **NodePool Template**
- Defines Spot instance requirements
- Available [here](../../nodepool-templates/spot-nodepool.yaml.tpl)
- Supports c, m, and r instance families
- ARM64 architecture for cost efficiency

🔄 **Load Balancer**
- Application Load Balancer (ALB)
- Exposes the application to external traffic

🎮 **Sample Application**
- 2048 game (sliding tile puzzle)
- Stateless application ideal for spot instances

## Implementation Steps

### 1. Deploy Spot NodePool
Deploy the NodePool that will manage our Spot instances:

```bash
kubectl apply -f ../../nodepools/spot-nodepool.yaml
```

> ⚠️ The Spot NodePool applies the following taint to ensure workloads are spot-aware:
>
> ```yaml
> taints:
>   - key: "spot"
>     value: "true"
>     effect: "NoSchedule"   # Prevents non-spot-aware pods from scheduling
> ```
>
> Any pods that need to run on Spot nodes must include matching tolerations in their specifications. This ensures workloads are designed to handle spot instance interruptions.

### 2. Deploy the 2048 Game
Deploy our spot-compatible 2048 game application:

```bash
kubectl apply -f game-2048.yaml
```

> ✅ The 2048 game deployment includes the required configuration for Spot instances:
>
> ```yaml
> tolerations:
>   - key: "spot"     # Matches the Spot node taint
>     value: "true"
>     effect: "NoSchedule"   # Allows scheduling on tainted nodes
>
> nodeSelector:
>   karpenter.sh/capacity-type: spot   # Ensures pods run on spot instances
> ```
>
> This configuration ensures the pods can run on Spot instances and are scheduled appropriately.

### 3. Configure Load Balancer
Set up the Application Load Balancer using Ingress:

```bash
kubectl apply -f 2048-ingress.yaml
```

### 4. Access the Application

By default, this example exposes its UI via an **internal ALB** — reachable from inside the VPC only. To access it from your laptop, use `kubectl port-forward`:

```bash
kubectl port-forward -n game-2048-spot svc/service-2048 8080:80
# then open http://localhost:8080
```

If you want to inspect the ALB DNS name directly (e.g. from a bastion or VPN):

```bash
kubectl get ingress ingress-2048 \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
  -n game-2048-spot
```

To expose the UI publicly over HTTPS, deploy the Terraform stack with `var.base_domain` set to a public Route53 zone you own (see top-level [README](../../README.md#-public-exposure-opt-in)). The example will be reachable at `https://2048-spot.<full_domain>` once external-dns publishes the record. 🎮

## Cleanup

🧹 Follow these steps to clean up all resources:

Remove the application and node pool:

```bash
kubectl delete -f 2048-ingress.yaml
kubectl delete -f game-2048.yaml
kubectl delete -f ../../nodepools/spot-nodepool.yaml
```

## Troubleshooting

🔧 Common issues and their solutions:

### 🎯 Spot Instance Issues
1. **Capacity Unavailability**
   - Monitor instance capacity with AWS CLI:
     ```bash
     aws ec2 describe-spot-instance-requests \
       --filters "Name=status-code,Values=capacity-not-available"
     ```
   - Check NodePool events:
     ```bash
     kubectl describe nodepool spot-nodepool
     ```

2. **Instance Interruptions**
   - Monitor interruption events:
     ```bash
     kubectl get events --field-selector reason=SpotInterruption
     ```
   - Review pod eviction status:
     ```bash
     kubectl get pods -n game-2048 -o wide
     ```

### 🔄 Load Balancer Issues
1. **ALB Configuration**
   ```bash
   # Check ALB controller logs
   kubectl logs -n kube-system \
     deployment/aws-load-balancer-controller
   ```

2. **Ingress Status**
   ```bash
   # Check ingress status
   kubectl describe ingress ingress-2048 -n game-2048
   ```

> 💡 **Tip**: Use `kubectl get events` to monitor spot instance lifecycle events and pod rescheduling.
