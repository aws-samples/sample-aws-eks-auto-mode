---
sidebar_position: 2
title: Cleanup Playbook
description: "EKS Auto Mode cleanup playbook — safely destroy clusters without orphaning EBS volumes, ALBs, ENIs, and security groups. 14-category post-destroy sweep."
keywords: [EKS cleanup, destroy EKS cluster, orphaned resources EKS, eks terraform destroy, clean up kubernetes]
---

# EKS Auto Mode — Cleanup Playbook

## Why `terraform destroy` alone fails

`aws_eks_cluster` deletion tears down the control plane but does NOT drain in-cluster workloads. CSI drivers and the ALB Controller lose their API server mid-reconcile, so PVCs become orphaned EBS volumes, Ingresses become orphaned ALBs/TGs, and EFS access points leak. This applies equally to Auto Mode and Standard Mode clusters.

## Drain-before-destroy order

1. **Delete all Ingresses** — triggers ALB Controller finalizers; wait 30-60s for ALB/TG deletion via `describe-load-balancers` polling.
2. **Delete LoadBalancer-type Services** — NLBs live here, separate from Ingress ALBs.
3. **Delete all PVCs** — triggers EBS CSI volume detach+delete; poll `describe-volumes` until cluster-tagged vols are gone.
4. **Remove KEDA ScaledObjects** — prevents rescaling during drain (skip if no KEDA CRDs).
5. **Uninstall Helm releases** — triggers external-dns record cleanup via finalizers.
6. **Delete custom NodePools + NodeClaims** — triggers node termination; skip the `general-purpose` pool (AWS-managed in Auto Mode).
7. **Wait for LB cleanup** — poll `elbv2.k8s.aws/cluster=<name>` tagged LBs (up to 3 min).
8. **Run `terraform destroy`** (KEDA sub-module first, then main).

## Post-destroy orphan checklist

Delete in this order (dependencies before parents):

| # | Resource type | How to find | Notes |
|---|---|---|---|
| 1 | Target Groups | `elbv2 describe-tags` with `elbv2.k8s.aws/cluster=<name>` | Delete before LBs |
| 2 | Load Balancers | Same tag filter | Delete listeners first |
| 3 | EC2 Instances | Tags: `karpenter.sh/discovery`, `aws:eks:cluster-name`, `kubernetes.io/cluster/<name>` | Terminate |
| 4 | EBS Volumes | `status=available` + tag `kubernetes.io/cluster/<name>` | Detached = safe to delete |
| 5 | ENIs | `status=available` + description/SG containing cluster name | |
| 6 | Security Groups | Name or tag contains cluster name | Revoke all rules first |
| 7 | IAM Roles | Name contains cluster name (skip `AWSServiceRole*`) | Detach policies first |
| 8 | OIDC Providers | ARN contains the 32-char OIDC ID (capture while cluster is alive) | |
| 9 | CloudWatch Logs | Prefix `/aws/eks/<name>` and `/aws/containerinsights/<name>` | |
| 10 | KMS Keys | Alias contains cluster name | Schedule deletion (7-day min) |
| 11 | Route53 Records | A/CNAME under `*.<domain>` + TXT with `txtOwnerId` | |
| 12 | SQS Queues | Queue name prefix = cluster name | |
| 13 | Launch Templates | Name or `aws:eks:cluster-name` tag | |
| 14 | Elastic IPs | Unassociated + name/tag containing cluster name | |

## Usage

```bash
./scripts/cleanup.sh [OPTIONS]

--dry-run          Show what would be deleted without deleting
--yes              Skip all prompts (full non-interactive delete)
--keep-storage     Preserve PVC/EBS/EFS resources
--region REGION    Override auto-detected region
--cluster-name N   Override auto-detected cluster name
--domain DOMAIN    Full domain for Route53 sweep
--skip-terraform   Orphan sweep only (TF already destroyed)
--skip-keda        Skip KEDA sub-module destroy
```

Common invocations:

```bash
./scripts/cleanup.sh --dry-run           # preview
./scripts/cleanup.sh --yes               # full non-interactive teardown
./scripts/cleanup.sh --skip-terraform --yes  # post-hoc orphan sweep
```

## Key gotchas (Auto Mode specific)

- **Managed `default` NodeClass tags revert silently** — always use a custom NodeClass for durable tags.
- **OIDC provider ID must be captured while cluster is alive** — script does this in Phase 1.
- **`provider default_tags` don't reach EKS primary SG** — pass via `cluster_tags`.
