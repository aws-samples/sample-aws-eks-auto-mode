---
sidebar_position: 1
title: "Skill: eks-automode-onboard"
description: "EKS Auto Mode onboarding skill for Claude Code. Covers concepts, deployment, example selection, and troubleshooting for newcomers to Auto Mode."
keywords: [eks auto mode, onboarding, getting started, claude code skill, deployment guide, troubleshooting]
---

# eks-automode-onboard

A Claude Code skill for users new to EKS Auto Mode who want to understand concepts and deploy using this repository.

## When to use

Trigger this skill when you:

- Want to understand what EKS Auto Mode manages
- Need to deploy your first Auto Mode cluster
- Are choosing which example fits your use case
- Hit a common first-day issue (Pending pods, tags not landing, LB not provisioning)

## What it covers

### Quick decision tree

Maps your use case to the right example directory:

| Use case | Example |
|----------|---------|
| First deployment / validation | `examples/graviton/` |
| Fault-tolerant batch / dev | `examples/spot/` |
| ML inference (NVIDIA GPU) | `examples/gpu/` |
| ML inference (Inferentia2) | `examples/neuron/` |
| OD + Spot mix with headroom | `examples/cost-optimization/` |
| Pin to reserved capacity | `examples/capacity-reservation/` |
| Fixed always-on fleet | `examples/static-capacity/` |
| Protect long-running jobs | `examples/batch-jobs/` |
| Limit drain concurrency | `examples/disruption-budgets/` |
| CPU autoscaling + SQS-driven | `examples/pod-autoscaling/` |
| Metrics, logs, tracing | `examples/observability/` |

### Key concepts

- What AWS manages vs what you manage (shared responsibility)
- NodePool and NodeClass relationship
- The `templatefile()` rendering chain
- Why you never edit the managed `default` NodeClass

### Common gotchas

1. Pods stuck Pending -- nodeSelector mismatch
2. Wrong EBS StorageClass provisioner name (`ebs.csi.eks.amazonaws.com`, not `ebs.csi.aws.com`)
3. Editing default NodeClass -- reverts silently
4. Tags not landing -- missing IAM custom-tags policy
5. No SSH/SSM access -- use `kubectl debug node/` or NodeDiagnostic
6. Stale rendered YAML after template edit -- run `terraform apply`
7. LB not provisioning -- missing subnet tags

### Reference docs (loaded on demand)

- `references/concepts.md` -- deep dive on managed components, instance families, IMDS, disruption model
- `references/deployment-guide.md` -- prerequisites, variable reference, post-deploy validation, cleanup
- `references/troubleshooting.md` -- 8 problem categories with solutions

## Sources

- [EKS Auto Mode overview](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Auto Mode best practices](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html)
- [Create a NodePool](https://docs.aws.amazon.com/eks/latest/userguide/create-node-pool.html)
- [Create a NodeClass](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html)
- [Troubleshooting Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/auto-troubleshoot.html)
- [This repository](https://github.com/aws-samples/sample-aws-eks-auto-mode)
