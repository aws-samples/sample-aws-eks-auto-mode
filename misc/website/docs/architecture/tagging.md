---
sidebar_position: 1
title: 5-Layer Tagging
description: "5-layer resource tagging for EKS Auto Mode — tag EC2 instances, EBS volumes, ENIs, ALBs, and security groups created by Kubernetes controllers for full cost allocation."
keywords: [EKS tagging, eks auto mode tags, kubernetes resource tagging, AWS cost allocation tags, tag EKS nodes]
---

# EKS Auto Mode — 5-Layer Tagging

## The problem

Terraform `provider "aws" { default_tags {} }` only reaches resources the provider creates directly. K8s controllers (Auto Mode's built-in Karpenter, EBS CSI, ALB controller) call AWS APIs under the cluster IAM role, completely outside Terraform's visibility. Without explicit per-controller configuration, EC2 instances, EBS volumes, ENIs, ALBs, and security groups all come up untagged.

## 5-layer pattern

1. **Provider `default_tags`** — covers all TF-direct resources (VPC, subnets, EKS cluster, IAM roles, KMS, S3, Lambda, ACM, etc.).
   - Code: `terraform/main.tf` provider block.
   - Gotcha: does NOT cascade to k8s-controller-created resources. Also blocked by `lifecycle { ignore_changes = [tags] }`.

2. **EKS `cluster_tags`** — tags the EKS-managed primary security group via `aws_ec2_tag` in the eks module (provider `default_tags` cannot reach it).
   - Code: `cluster_tags` input on the `module.eks` block in `terraform/eks.tf`.
   - Gotcha: must be passed as `cluster_tags`, not `tags`. The primary SG is created by the EKS service, not TF.

3. **Custom NodeClass `spec.tags`** — tags EC2 instances, root EBS volumes, and ENIs launched by Auto Mode's Karpenter.
   - Code: `nodepool-templates/*.yaml.tpl` (each template includes `spec.tags: ${indent(4, yamlencode(tags))}`).
   - **WARNING: never patch the managed `default` NodeClass.** EKS's reconciler silently reverts custom fields within minutes. Always create a named custom NodeClass you own.
   - NodePools must reference the custom NodeClass via `nodeClassRef.name`.

4. **StorageClass `tagSpecification_N`** — tags EBS volumes created by PVCs.
   - Code: `terraform/tagging.tf` (`kubectl_manifest.storageclass_ebs`).
   - Gotcha: StorageClass `parameters` is immutable. Updates require delete + recreate. Existing PVCs keep their original (untagged) volumes.

5. **IngressClassParams `spec.tags`** — tags ALBs, target groups, listeners, and listener-rule SGs created by Auto Mode's built-in ALB controller.
   - Code: `terraform/ingressclass.tf` (`kubectl_manifest.ingressclassparams_*`).
   - Gotcha: per-IngressClassParams, so tag each one if you have multiple (internal vs internet-facing).

## IAM tagging policy

**Load-bearing.** Without it, layers 3-5 silently fail.

Auto Mode's managed policies (`AmazonEKSComputePolicy`, `AmazonEKSBlockStoragePolicy`, `AmazonEKSLoadBalancingPolicy`, `AmazonEKSNetworkingPolicy`) use `ForAllValues:StringEquals "aws:TagKeys"` to allowlist only `eks:*`, `kubernetes.io/*`, `karpenter.sh/*` tag keys. Any request carrying a custom key (e.g. `auto-delete`) falls outside the allowlist, so the managed Allow does not match and the call is DENIED (`UnauthorizedOperation`).

Fix: the EKS Terraform module (v20.31+) handles this automatically via `enable_auto_mode_custom_tags = true` (default). It attaches a managed policy to the cluster role with the same actions scoped via `aws:RequestTag/eks:eks-cluster-name = ${aws:PrincipalTag/eks:eks-cluster-name}`.

- Code: `terraform/eks.tf` (`enable_auto_mode_custom_tags = true` on the module block)
- [AWS docs: cluster IAM role tag propagation](https://docs.aws.amazon.com/eks/latest/userguide/auto-cluster-iam-role.html#tag-prop)

## Known gap

**LoadBalancer-type Services** (not Ingress) need the annotation `service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags` set per-Service. There is no cluster-wide default for this.

## `default_tags` does NOT reach

- EC2 instances launched by Karpenter/Auto Mode
- EBS volumes created by the EBS CSI driver (PVC-provisioned)
- ENIs created by the VPC CNI
- ALBs/NLBs created by the ALB controller
- Target groups, listeners, listener rules
- Security groups created by the ALB controller or EKS networking
- EKS primary security group (use `cluster_tags` / `aws_ec2_tag`)
- EFS access points created by the EFS CSI driver
- Shield protections created by the ALB controller

## Debugging: tag not landing?

1. Check CloudTrail for `ErrorCode=UnauthorizedOperation` on RunInstances/CreateVolume — means IAM policy is missing.
2. Check if someone patched the managed `default` NodeClass — it reverts silently.
3. Verify StorageClass was recreated (parameters are immutable, `kubectl apply` on changed params errors).
4. For existing resources: tags only apply to future creates. Retag imperatively with `aws ec2 create-tags` / `aws elbv2 add-tags`.
