---
sidebar_position: 8
title: Static Capacity Pools
---

# Static Capacity Pools

## What are static capacity pools?

Setting `spec.replicas` on a NodePool tells EKS Auto Mode to maintain exactly N nodes at all times, regardless of pod demand. These nodes are never consolidated away when empty. They exist whether workloads are scheduled on them or not.

```yaml
spec:
  replicas: 2   # Always maintain exactly 2 nodes
```

## Why they exist

Some workloads need guaranteed capacity available at all times:

- **Always-on inference endpoints** that must respond in milliseconds, not minutes
- **Database replicas** where cold-start means replay from WAL/snapshot
- **License-bound software** where the license is tied to a running host
- **Latency-sensitive services** where waiting for a node to provision (30-90s) is unacceptable

Dynamic scaling introduces cold-start latency. For workloads where that latency violates SLOs, static pools eliminate it entirely.

## How it differs from dynamic pools

| Behavior | Dynamic Pool | Static Pool |
|----------|-------------|-------------|
| Scale-from-zero | Yes | No -- always N nodes |
| Consolidation | Removes underutilized nodes | Never removes nodes |
| Scaling trigger | Pending pods | Manual (`kubectl scale nodepool`) |
| Cost model | Pay only for what you use | Pay for N nodes 24/7 |
| Cold-start risk | Yes (30-90s node provision) | None |

You can resize a static pool at any time:

```bash
kubectl scale nodepool static-gpu-nodepool --replicas=4
```

## The trade-off

You pay for N nodes 24/7 whether they are fully loaded or completely idle. Use static pools only where:

> **Cost of idle nodes < Cost of cold-start latency**

If your workload can tolerate 60-90 seconds of scale-up time, a dynamic pool is cheaper.

## When to use

- Always-on model serving (vLLM, TGI, Triton)
- Stateful databases (PostgreSQL, Redis cluster nodes)
- License servers (FlexLM, RLM)
- Baseline capacity layer -- handle steady-state traffic with static nodes, burst traffic with a separate dynamic pool

## Deploy

```bash
# Render the template (if using Terraform templatefile)
terraform apply

# Or apply directly after filling variables
kubectl apply -f static-nodepool.yaml
```

## What to observe

```bash
# Verify exactly 2 nodes exist for this pool (even with zero pods)
kubectl get nodes -l karpenter.sh/nodepool=static-gpu-nodepool

# Confirm replicas are set
kubectl get nodepool static-gpu-nodepool -o jsonpath='{.spec.replicas}'

# Watch that consolidation does NOT touch these nodes
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f | grep static-gpu

# Scale up
kubectl scale nodepool static-gpu-nodepool --replicas=4
# Watch a new node provision immediately (no pending pod required)
kubectl get nodes -w -l karpenter.sh/nodepool=static-gpu-nodepool
```
