# Setting up EKS Auto Mode using Terraform

## Table of Contents
- [Overview](#overview)
- [What's New](#whats-new)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Components](#components)
- [Examples](#examples)
- [Cleanup](#cleanup)
- [Security Considerations](#security-considerations)
- [Learn More](#learn-more)
- [Contributing](#contributing)
- [License and Disclaimer](#license-and-disclaimer)

## Overview

[Amazon EKS Auto Mode](https://aws.amazon.com/eks/auto-mode/) simplifies Kubernetes cluster management by automating compute, storage, and networking decisions. Under the hood it runs Karpenter, the AWS Load Balancer Controller, and the EBS CSI driver as managed components — you get the benefits without installing or upgrading any of them.

This repository is an educational companion. Each example demonstrates a specific EKS Auto Mode pattern (Graviton, GPU, Spot, ODCR targeting, disruption budgets, etc.) with a self-contained README explaining the "why" alongside the "how." Deploy the base cluster once, then apply individual examples to explore.

**Key capabilities covered:**

- Graviton (ARM64) and x86 workloads side by side
- GPU and Inferentia2 (Neuron) ML inference
- Spot and On-Demand mixed pools with overprovision headroom
- On-Demand Capacity Reservation targeting
- Static capacity pools and disruption budgets
- HPA and KEDA-driven autoscaling
- KMS encryption for ephemeral node storage
- CloudWatch Container Insights observability
- 5-layer resource tagging for cost allocation

## What's New

Recent additions to this repository:

- **Disruption budgets** — control how many nodes Auto Mode can drain simultaneously during consolidation
- **ODCR targeting** — pin workloads to On-Demand Capacity Reservations so reserved capacity is actually consumed
- **Static capacity pools** — maintain a fixed fleet of always-on nodes using `spec.replicas`
- **KMS encryption** — encrypt ephemeral storage on Auto Mode nodes with a customer-managed KMS key
- **Observability** — one-toggle CloudWatch Container Insights integration (metrics, logs, traces)
- **Cost optimization patterns** — OD/Spot split plus pause-pod overprovision headroom
- **Expanded instance families** — broader Graviton and GPU instance family coverage in NodePool templates
- **Batch job protection** — `do-not-disrupt` annotations and dedicated NodePools for long-running jobs
- **Educational examples** — every example now has a detailed README explaining the underlying mechanics

## Prerequisites

**Required Tools:**
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

> **Note**: This project currently provides Linux-specific commands in the examples. Windows compatibility will be added in future updates.

## Quick Start

1. **Clone Repository**:
```bash
git clone https://github.com/aws-samples/sample-aws-eks-auto-mode.git
cd sample-aws-eks-auto-mode
```

2. **Deploy Cluster**:
```bash
cd terraform
terraform init
terraform apply -auto-approve

# Configure kubectl
$(terraform output -raw configure_kubectl)
```

3. **Apply an example** (e.g., Graviton):
```bash
kubectl apply -f examples/graviton/
```

## Configuration

All inputs are defined in `terraform/variables.tf`. Override them with `-var` flags or a `terraform.tfvars` file.

| Variable | Description | Default |
|----------|-------------|---------|
| `name` | Name of the VPC and EKS cluster | `automode-cluster` |
| `region` | AWS region to deploy into | `us-west-2` |
| `eks_cluster_version` | EKS Kubernetes version | `1.34` |
| `vpc_cidr` | VPC CIDR block (RFC 1918) | `10.0.0.0/16` |
| `tags` | Tags applied to every taggable resource (provider default\_tags, EKS primary SG, NodeClass EC2/EBS/ENI, StorageClass EBS, ALB) | `{"auto-delete" = "never"}` |
| `base_domain` | Public Route53 hosted zone for HTTPS exposure. Leave empty for internal-only (safe-by-default). | `""` |
| `subdomain` | Optional prefix under `base_domain` (e.g., `automode` gives `automode.example.com`). Ignored when `base_domain` is empty. | `""` |
| `ephemeral_storage_kms_key_id` | KMS key ID for encrypting ephemeral node storage. Leave empty for default encryption. | `""` |
| `enable_observability` | Enable CloudWatch Container Insights addon (metrics, logs, Application Signals). Incurs CloudWatch costs. | `false` |

**Example — public exposure with observability:**
```bash
terraform apply \
  -var='base_domain=example.com' \
  -var='subdomain=automode' \
  -var='enable_observability=true'
```

## Components

### How EKS Auto Mode Works

EKS Auto Mode bundles three managed controllers into the EKS control plane:

1. **Karpenter** — provisions and consolidates EC2 nodes based on pending pod requirements.
2. **AWS Load Balancer Controller** — creates ALBs/NLBs from Ingress and Service resources.
3. **EBS CSI Driver** — provisions and attaches EBS volumes from PersistentVolumeClaims.

You never install these yourself. EKS upgrades them transparently. You interact with them through standard Kubernetes APIs: NodePool, NodeClass, Ingress, IngressClassParams, StorageClass.

### NodePool → NodeClass → EC2 Flow

The provisioning path:

```
Pod pending → Karpenter matches NodePool constraints (instance families, AZs, capacity type)
           → NodePool references a NodeClass (subnet selection, security groups, tags, storage)
           → Karpenter launches an EC2 instance matching the constraints
           → kubelet registers the node and the pod is scheduled
```

**NodePools** define what to launch (instance types, architectures, capacity type, taints/labels). **NodeClasses** define how to launch (subnets, SGs, ephemeral storage, tags pushed to EC2/EBS/ENI).

### 5-Layer Tagging

Getting cost-allocation tags onto every resource requires five layers because different resources are created by different actors:

| Layer | Mechanism | Reaches |
|-------|-----------|---------|
| 1 | Terraform `default_tags` | All Terraform-managed resources |
| 2 | `cluster_tags` on the EKS module | EKS-created primary security group |
| 3 | `spec.tags` on custom NodeClasses | EC2 instances, EBS volumes, ENIs launched by Karpenter |
| 4 | StorageClass `tagSpecification` | EBS volumes created by the CSI driver |
| 5 | IngressClassParams `tags` | ALBs/NLBs created by the LB controller |

The Terraform code in this repo wires all five layers from a single `var.tags` input.

### Load Balancer Configuration

EKS Auto Mode automates ALB and NLB setup:

- **Application Load Balancer (ALB)** — IngressClass-based, supports shared ALB groups across namespaces. [Docs](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html)
- **Network Load Balancer (NLB)** — Native Kubernetes Service type LoadBalancer. [Docs](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-nlb.html)

> **Subnet tagging requirement**: If subnet IDs are not explicit in IngressClassParams, subnets need `kubernetes.io/role/elb: "1"` (public) or `kubernetes.io/role/internal-elb: "1"` (private). The Terraform code in this repo adds these tags automatically.

#### Public exposure (opt-in)

By default this stack is **safe-by-default**: every example workload exposes an *internal-scheme* load balancer reachable only via `kubectl port-forward`. Nothing is published to the public internet without an explicit opt-in.

To expose the example workloads on a real domain over HTTPS, set `var.base_domain` (and optionally `var.subdomain`) to a public Route53 hosted zone you already own:

```bash
terraform apply -var='base_domain=example.com' -var='subdomain=automode'
```

When `base_domain` is set, Terraform will:

- Look up the existing public hosted zone (it does **not** create one — the zone must already exist and be the authoritative DNS for that name).
- Issue an ACM wildcard certificate `*.<subdomain>.<base_domain>` validated via DNS records added to the zone.
- Install [external-dns](https://github.com/kubernetes-sigs/external-dns) bound to a Pod Identity IAM role scoped to **only** that hosted zone (not `Route53FullAccess`).
- Switch the cluster-wide `IngressClass alb` to `internet-facing` with a shared ALB group so all example Ingresses share one load balancer.
- Render each example with a public hostname and the appropriate annotations.

Workload hostnames once enabled:

| Example | URL |
|---|---|
| `examples/graviton` | `https://2048-graviton.<full_domain>` |
| `examples/spot` | `https://2048-spot.<full_domain>` |
| `examples/gpu` | `https://gpu.<full_domain>` |
| `examples/neuron` | `https://neuron.<full_domain>` |

The ALB controller picks the right certificate via SNI from each Ingress's `host:` against the wildcard cert — no `certificateArn` is configured anywhere.

To revert to safe-by-default, unset `var.base_domain` and re-apply.

### EBS CSI Driver

EKS Auto Mode includes the EBS CSI driver as a managed component — no installation required.

- Only volumes provisioned from a StorageClass using `ebs.csi.eks.amazonaws.com` can mount on Auto Mode nodes.
- Existing volumes need migration via volume snapshots.
- Custom KMS encryption may require additional IAM permissions.

[AWS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)

## Examples

Each example has its own README with detailed explanations of the underlying mechanics.

### Compute Patterns

| Example | Description |
|---------|-------------|
| [Graviton](examples/graviton/) | ARM64 workloads on cost-effective Graviton instances. Deploys a 2048 game. |
| [Spot](examples/spot/) | Fault-tolerant workloads on EC2 Spot with diverse instance families. Deploys a 2048 game. |
| [GPU](examples/gpu/) | GPU-accelerated ML inference (Qwen 3 on NVIDIA GPUs). |
| [Neuron](examples/neuron/) | ML inference on AWS Inferentia2 (DeepSeek-R1-Qwen3-8B served by vLLM). |

### Cost Optimization

| Example | Description |
|---------|-------------|
| [Cost Optimization](examples/cost-optimization/) | OD/Spot mixed pools with weighted priorities and pause-pod overprovision headroom. |

### Advanced Scheduling

| Example | Description |
|---------|-------------|
| [Capacity Reservation](examples/capacity-reservation/) | Pin workloads to On-Demand Capacity Reservations (ODCRs) so reserved capacity is consumed. |
| [Static Capacity](examples/static-capacity/) | Maintain a fixed fleet of always-on nodes using `spec.replicas`, immune to consolidation. |
| [Batch Jobs](examples/batch-jobs/) | Protect long-running jobs from eviction using `do-not-disrupt` annotations and dedicated NodePools. |
| [Disruption Budgets](examples/disruption-budgets/) | Limit simultaneous node drains during consolidation to prevent cascading failures. |

### Autoscaling

| Example | Description |
|---------|-------------|
| [Pod Autoscaling](examples/pod-autoscaling/) | HPA for CPU-based scaling plus KEDA for event-driven scaling (SQS queue depth). |

### Observability

| Example | Description |
|---------|-------------|
| [Observability](examples/observability/) | CloudWatch Container Insights integration for metrics, pod logs, and Application Signals tracing. |

## Cleanup

A standalone cleanup script handles the full teardown lifecycle — draining Kubernetes-controller-managed AWS resources (ALBs, EBS volumes, EC2 instances) before `terraform destroy`, then sweeping for any orphans that survived.

```bash
# Recommended: interactive cleanup (prompts per resource)
./scripts/cleanup.sh

# Non-interactive: delete everything
./scripts/cleanup.sh --yes

# Preview what would be deleted
./scripts/cleanup.sh --dry-run

# Delete everything except storage (PVCs/EBS)
./scripts/cleanup.sh --yes --keep-storage

# Orphan sweep only (terraform already destroyed)
./scripts/cleanup.sh --skip-terraform --cluster-name <name> --region <region>
```

The script runs in three phases:
1. **Pre-drain** — deletes Ingresses, LoadBalancer Services, PVCs, Helm releases, NodePools/NodeClaims while the cluster API is alive so controllers can fire finalizers and release AWS resources.
2. **Terraform destroy** — runs `terraform init` + `destroy` for both the main and KEDA terraform roots.
3. **Orphan sweep** — scans for resources tagged with the cluster name (or matching known patterns for untaggable resources like Auto Mode internal volumes) and prompts for deletion.

> **Why not just `terraform destroy`?** A bare `terraform destroy` doesn't drain Kubernetes-managed resources first. ALBs, EBS volumes, EC2 instances, and ENIs created by in-cluster controllers (ALB controller, EBS CSI, Karpenter) are not in Terraform state — they persist as orphans after the cluster is gone. The cleanup script handles these.

<details>
<summary>Manual alternative (not recommended)</summary>

```bash
cd terraform
terraform init
terraform destroy --auto-approve
```

This only destroys Terraform-managed resources. You will need to manually find and delete any orphaned load balancers, volumes, instances, security groups, IAM roles, OIDC providers, and CloudWatch log groups.
</details>

## Security Considerations
Our code is continuously scanned using [Checkov](https://www.checkov.io/5.Policy%20Index/kubernetes.html). The following security considerations are documented for transparency:

|Checks	|Details	|Reasons	|
|---	|---	|---	|
|CKV_TF_1	|Ensure Terraform module sources use a commit hash	|For easy experimentation, we set version of module, instead of setting a commit hash. Consider implementing a commit hash in a production cluster. [Read more on why we need to set commit hash for modules here.](https://medium.com/boostsecurity/erosion-of-trust-unmasking-supply-chain-vulnerabilities-in-the-terraform-registry-2af48a7eb2)	|
|CKV2_K8S_6	|Minimize the admission of pods which lack an associated NetworkPolicy	|All Pod to Pod communication is allowed by default for easy experimentation in this project. Amazon VPC CNI now supports [Kubernetes Network Policies](https://aws.amazon.com/blogs/containers/amazon-vpc-cni-now-supports-kubernetes-network-policies/) to secure network traffic in kubernetes clusters	|
|CKV_K8S_8	|Liveness Probe Should be Configured	|For easy experimentation, no health checks is to be performed against the container to determine whether it is alive or not. Consider implementing [health checks](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) in a production cluster.	|
|CKV_K8S_9	|Readiness Probe Should be Configured	|For easy experimentation, no health checks is to be performed against the container to determine whether it is alive or not. Consider implementing health checks in a production cluster.	|
|CKV_K8S_22	|Use read-only filesystem for containers where possible	|We've made an exception for the workloads that requires are Read/Write file system. [Configure your images with read-only root file system](https://docs.aws.amazon.com/eks/latest/best-practices/pod-security.html#_configure_your_images_with_read_only_root_file_system)	|
|CKV_K8S_23	|Minimize the admission of root containers	|This project uses default root container configurations for demonstration purposes. While this doesn't follow security best practices, it ensures compatibility with demo images. For production, configure runAsNonRoot: true and follow [guidance](https://docs.docker.com/engine/reference/builder/#user) on building images with specified user ID.  	|
|CKV_K8S_37	|Minimize the admission of containers with capabilities assigned	|For easy experimentation, we've made exception for the workloads that requires added capability. For production purposes, we recommend [capabilities field](https://docs.aws.amazon.com/eks/latest/best-practices/pod-security.html#_linux_capabilities) that allows granting certain privileges to a process without granting all the privileges of the root user.  	|
|CKV_K8S_40	|Containers should run as a high UID to avoid host conflict	|We've used publicly available container images in this project for customers' easy access. For test purposes, the container images user id are left intact. See [how to define UID](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod).	| 

## Learn More

- [EKS Auto Mode documentation](https://docs.aws.amazon.com/eks/latest/userguide/automode.html) — official AWS guide covering setup, NodePools, NodeClasses, and managed components
- [Karpenter documentation](https://karpenter.sh/docs/) — the provisioner that powers Auto Mode's compute layer; useful for understanding NodePool/NodeClass semantics
- [karpenter-blueprints](https://github.com/aws-samples/karpenter-blueprints) — additional Karpenter patterns beyond what this repo covers
- [platform-engineering-on-eks](https://github.com/aws-samples/platform-engineering-on-eks) — broader platform engineering patterns on EKS

## Contributing
Contributions welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md).

## License and Disclaimer

### License
This project is licensed under the MIT License - see [LICENSE](LICENSE) file.

### Disclaimer
**This repository is intended for demonstration and learning purposes only.**
It is **not** intended for production use. The code provided here is for educational purposes and should not be used in a live environment without proper testing, validation, and modifications.

Use at your own risk. The authors are not responsible for any issues, damages, or losses that may result from using this code in production.

In this samples, there may be use of third-party models ("Third-Party Models") that AWS does not own, and that AWS does not exercise control over. By using any prototype or proof of concept from AWS you acknowledge that the Third-Party Models are "Third-Party Content" under your agreement for services with AWS. You should perform your own independent assessment of the Third-Party Models. You should also take measures to ensure that your use of the Third-Party Models complies with your own specific quality control practices and standards, and the local rules, laws, regulations, licenses and terms of use that apply to you, your content, and the Third-Party Models. AWS does not make any representations or warranties regarding the Third-Party Models, including that use of the Third-Party Models and the associated outputs will result in a particular outcome or result. You also acknowledge that outputs generated by the Third-Party Models are Your Content/Customer Content, as defined in the AWS Customer Agreement or the agreement between you and AWS for AWS Services. You are responsible for your use of outputs from the Third-Party Models.
