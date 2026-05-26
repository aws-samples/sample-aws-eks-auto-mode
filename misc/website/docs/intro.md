---
sidebar_position: 1
title: Introduction
---

# EKS Auto Mode Samples

[Amazon EKS Auto Mode](https://aws.amazon.com/eks/auto-mode/) simplifies Kubernetes cluster management by automating compute, storage, and networking decisions. Under the hood it runs Karpenter, the AWS Load Balancer Controller, and the EBS CSI driver as managed components — you get the benefits without installing or upgrading any of them.

This repository is an educational companion. Each example demonstrates a specific EKS Auto Mode pattern (Graviton, GPU, Spot, ODCR targeting, disruption budgets, etc.) with a self-contained README explaining the "why" alongside the "how." Deploy the base cluster once, then apply individual examples to explore.

## Key capabilities covered

- Graviton (ARM64) and x86 workloads side by side
- GPU and Inferentia2 (Neuron) ML inference
- Spot and On-Demand mixed pools with overprovision headroom
- On-Demand Capacity Reservation targeting
- Static capacity pools and disruption budgets
- HPA and KEDA-driven autoscaling
- KMS encryption for ephemeral node storage
- CloudWatch Container Insights observability
- 5-layer resource tagging for cost allocation

## What's in this repo

| Directory | Purpose |
|-----------|---------|
| `terraform/` | Base cluster infrastructure (VPC, EKS, IAM, NodePools) |
| `examples/` | Self-contained deployable patterns |
| `nodepool-templates/` | Templatized NodePool/NodeClass definitions |
| `scripts/` | Cleanup and maintenance utilities |
| `claude-md/` | Architecture reference docs (tagging, cleanup) |

## Where to go next

- [Getting Started](./getting-started) — deploy the base cluster
- [Examples](./examples) — browse deployable patterns
- [Architecture](./architecture) — tagging, cleanup, security
- [Contributing](./contributing) — improve this repo
