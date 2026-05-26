---
sidebar_position: 3
title: Security Considerations
description: "EKS Auto Mode security considerations — Checkov scan results, security trade-offs, and hardening guidance for Kubernetes on AWS."
keywords: [EKS security, eks auto mode security, kubernetes security AWS, Checkov EKS, harden kubernetes]
---

# Security Considerations

Our code is continuously scanned using [Checkov](https://www.checkov.io/5.Policy%20Index/kubernetes.html). The following security considerations are documented for transparency:

| Check | Details | Reason |
|-------|---------|--------|
| CKV_TF_1 | Ensure Terraform module sources use a commit hash | For easy experimentation, we set version of module instead of a commit hash. Consider implementing a commit hash in production. [Read more](https://medium.com/boostsecurity/erosion-of-trust-unmasking-supply-chain-vulnerabilities-in-the-terraform-registry-2af48a7eb2) |
| CKV2_K8S_6 | Minimize pods without NetworkPolicy | All Pod-to-Pod communication is allowed for experimentation. Amazon VPC CNI supports [Kubernetes Network Policies](https://aws.amazon.com/blogs/containers/amazon-vpc-cni-now-supports-kubernetes-network-policies/) for production. |
| CKV_K8S_8 | Liveness Probe Should be Configured | No health checks for experimentation. Implement [health checks](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) in production. |
| CKV_K8S_9 | Readiness Probe Should be Configured | Same as above. |
| CKV_K8S_22 | Use read-only filesystem where possible | Exception for workloads requiring R/W. [Configure read-only root](https://docs.aws.amazon.com/eks/latest/best-practices/pod-security.html#_configure_your_images_with_read_only_root_file_system). |
| CKV_K8S_23 | Minimize root containers | Default root containers for demo compatibility. For production, use `runAsNonRoot: true`. |
| CKV_K8S_37 | Minimize containers with capabilities | Exception for workloads requiring added capability. See [capabilities guidance](https://docs.aws.amazon.com/eks/latest/best-practices/pod-security.html#_linux_capabilities). |
| CKV_K8S_40 | Run as high UID | Public container images used as-is. See [how to define UID](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod). |
