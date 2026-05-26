---
sidebar_position: 8
title: Static Capacity Pools
---

# Static Capacity Pools

## What are static capacity pools?

Setting `spec.replicas` on a NodePool tells EKS Auto Mode to maintain exactly N nodes at all times, regardless of pod demand. These nodes are never consolidated away when empty. They exist whether workloads are scheduled on them or not.

## Prerequisites

Cluster deployed and `kubectl` configured per [Quick Start](../../README.md#quick-start).

```yaml
spec:
  replicas: 2   # Always maintain exactly 2 nodes
```

## Why they exist

Some workloads need guaranteed capacity available at all times:

- **Always-on inference endpoints** that must respond in milliseconds, not minutes
- **License-bound software** where the license is tied to a running host
- **Latency-sensitive services** where waiting for a node to provision (30-90s) is unacceptable

Dynamic scaling introduces cold-start latency. For workloads where that latency violates SLOs, static pools eliminate it entirely.

## How it differs from dynamic pools

| Behavior | Dynamic Pool | Static Pool |
|----------|-------------|-------------|
| Scale-from-zero | Yes | No -- always N nodes |
| Consolidation | Removes underutilized nodes | Never removes nodes |
| Scaling trigger | Pending pods | Manual (edit `spec.replicas`) |
| Cost model | Pay only for what you use | Pay for N nodes 24/7 |
| Cold-start risk | Yes (30-90s node provision) | None |

You can resize a static pool at any time:

```bash
kubectl patch nodepool static-gpu-nodepool --type=merge -p '{"spec":{"replicas":4}}'
```

## The trade-off

You pay for N nodes 24/7 whether they are fully loaded or completely idle. Use static pools only where:

> **Cost of idle nodes < Cost of cold-start latency**

If your workload can tolerate 60-90 seconds of scale-up time, a dynamic pool is cheaper.

## When to use

- Always-on model serving (vLLM, TGI, Triton)
- License servers (FlexLM, RLM)
- Baseline capacity layer -- handle steady-state traffic with static nodes, burst traffic with a separate dynamic pool

## Deploy

> **Cost warning:** This example provisions GPU instances (`g6e` family) which are billed per-second while running. Nodes will launch immediately upon apply and persist until you clean up. Estimated cost: ~$1.50/hr per node.

```bash
kubectl apply -f static-nodepool.yaml
```

## What to observe

Verify exactly 2 nodes exist for this pool (even with zero pods):

```bash
kubectl get nodes -l karpenter.sh/nodepool=static-gpu-nodepool
```

Confirm replicas are set:

```bash
kubectl get nodepool static-gpu-nodepool -o jsonpath='{.spec.replicas}'
```

Watch that consolidation does NOT touch these nodes:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f | grep static-gpu
```

## Clean up

```bash
kubectl delete -f .
```
