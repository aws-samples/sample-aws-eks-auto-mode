---
sidebar_position: 2
title: Getting Started
description: "Get started with EKS Auto Mode — deploy an automated Kubernetes cluster in minutes using Terraform. Step-by-step setup guide for AWS EKS Auto Mode."
keywords: [EKS Auto Mode setup, eks auto mode terraform, getting started EKS, deploy EKS cluster, kubernetes quickstart]
---

# Getting Started

## Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) configured with appropriate credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) >= 1.5

## Deploy the base cluster

```bash
git clone https://github.com/aws-samples/sample-aws-eks-auto-mode.git
cd sample-aws-eks-auto-mode/terraform
terraform init
terraform apply -auto-approve
```

Configure kubectl:

```bash
$(terraform output -raw configure_kubectl)
```

## Apply an example

Each example is self-contained. Pick one and apply:

```bash
kubectl apply -f examples/graviton/
```

## Configuration

All inputs are defined in `terraform/variables.tf`. Override with `-var` flags or a `terraform.tfvars` file.

| Variable | Description | Default |
|----------|-------------|---------|
| `name` | VPC and EKS cluster name | `automode-cluster` |
| `region` | AWS region | `us-west-2` |
| `eks_cluster_version` | Kubernetes version | `1.34` |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `tags` | Tags applied to all resources (5-layer) | `{"auto-delete" = "never"}` |
| `base_domain` | Route53 zone for HTTPS (empty = internal-only) | `""` |
| `subdomain` | Prefix under base_domain | `""` |
| `ephemeral_storage_kms_key_id` | KMS key for node storage encryption | `""` |
| `enable_observability` | CloudWatch Container Insights | `false` |

### Public exposure (opt-in)

By default, all workloads are internal-only. To expose on a real domain:

```bash
terraform apply \
  -var='base_domain=example.com' \
  -var='subdomain=automode' \
  -var='enable_observability=true'
```

## Cleanup

```bash
./scripts/cleanup.sh
```

See [Cleanup Architecture](./architecture/cleanup) for the full teardown playbook.
