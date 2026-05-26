---
sidebar_position: 3
title: Examples
---

# Examples

Each example is a self-contained deployable pattern with its own README explaining the "why" alongside the "how." Deploy the base cluster once, then apply individual examples to explore.

## Compute Patterns

| Example | Description |
|---------|-------------|
| [Graviton](./graviton) | ARM64 workloads on cost-effective Graviton instances |
| [Spot](./spot) | Fault-tolerant workloads on EC2 Spot with diverse instance families |
| [GPU](./gpu) | GPU-accelerated ML inference (Qwen 3 on NVIDIA GPUs) |
| [Neuron](./neuron) | ML inference on AWS Inferentia2 (DeepSeek-R1 served by vLLM) |

## Cost Optimization

| Example | Description |
|---------|-------------|
| [Cost Optimization](./cost-optimization) | OD/Spot mixed pools with weighted priorities and pause-pod overprovision |

## Advanced Scheduling

| Example | Description |
|---------|-------------|
| [Capacity Reservation](./capacity-reservation) | Pin workloads to On-Demand Capacity Reservations (ODCRs) |
| [Static Capacity](./static-capacity) | Fixed fleet of always-on nodes using `spec.replicas` |
| [Batch Jobs](./batch-jobs) | Protect long-running jobs from eviction with `do-not-disrupt` |
| [Disruption Budgets](./disruption-budgets) | Limit simultaneous node drains during consolidation |

## Autoscaling

| Example | Description |
|---------|-------------|
| [Pod Autoscaling](./pod-autoscaling) | HPA for CPU-based scaling + KEDA for event-driven scaling |

## Observability

| Example | Description |
|---------|-------------|
| [Observability](./observability) | CloudWatch Container Insights integration |
