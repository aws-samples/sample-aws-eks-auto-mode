# EKS Auto Mode -- Deployment Guide

Complete walkthrough for deploying an EKS Auto Mode cluster using this repository.

## Prerequisites

### Required tools

| Tool | Minimum version | Purpose |
|------|-----------------|---------|
| AWS CLI | v2.x | AWS API access, kubectl config |
| Terraform | >= 1.5 | Infrastructure provisioning |
| kubectl | >= 1.29 | Cluster interaction |

### Optional tools

| Tool | Purpose |
|------|---------|
| Helm | Only if deploying KEDA example (pod-autoscaling) |
| jq | JSON parsing for validation commands |

### AWS account requirements

- An AWS account with permissions to create VPC, EKS, IAM, EC2, EBS, ELB, KMS,
  CloudWatch, and Route53 resources.
- A region that supports EKS Auto Mode (most commercial regions do; check the
  regional availability table in the EKS documentation).
- If using `base_domain`: a public Route53 hosted zone that already exists and is
  authoritative for that domain.

### Authentication

Configure AWS credentials before running Terraform:

```bash
aws sts get-caller-identity
```

This must return a valid identity with sufficient permissions.

## Variable reference

All inputs live in `terraform/variables.tf`. Override via `-var` flags or
`terraform/terraform.tfvars`.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | string | `automode-cluster` | Name for VPC and EKS cluster. Used in resource naming and tag discovery. |
| `region` | string | `us-west-2` | AWS region to deploy into. |
| `eks_cluster_version` | string | `1.34` | EKS K8s version. Auto Mode requires 1.29+. |
| `vpc_cidr` | string | `10.0.0.0/16` | VPC CIDR block. 65536 IPs across 3 AZs. |
| `tags` | map(string) | `{"auto-delete"="never"}` | Tags applied via 5-layer pattern to all taggable resources. |
| `base_domain` | string | `""` | Public Route53 zone for HTTPS. Leave empty for internal-only (safe default). |
| `subdomain` | string | `""` | Optional prefix under `base_domain`. Ignored when `base_domain` is empty. |
| `ephemeral_storage_kms_key_id` | string | `""` | KMS key ID for node ephemeral storage encryption. |
| `enable_observability` | bool | `false` | Enable CloudWatch Container Insights (incurs costs). |

### Minimal deploy (all defaults)

No tfvars file needed. Just run `terraform apply`.

### Production-like deploy

```hcl
# terraform/terraform.tfvars
name                  = "my-cluster"
region                = "eu-west-1"
eks_cluster_version   = "1.34"
tags                  = { "team" = "platform", "env" = "staging", "auto-delete" = "7d" }
base_domain           = "example.com"
subdomain             = "eks"
enable_observability  = true
```

## Deploy steps

### 1. Clone the repository

```bash
git clone https://github.com/aws-samples/sample-aws-eks-auto-mode.git && cd sample-aws-eks-auto-mode
```

### 2. Initialize Terraform

```bash
cd terraform && terraform init
```

Downloads providers (AWS, Kubernetes, Helm, kubectl) and the EKS module.

### 3. Plan (optional but recommended)

```bash
terraform plan -out=tfplan
```

Review the plan to understand what will be created (~45-60 resources for the base
cluster).

### 4. Apply

```bash
terraform apply tfplan    # if you saved a plan
# or
terraform apply -auto-approve
```

Takes 12-18 minutes. The EKS cluster creation is the longest step (~10 min).

### 5. Configure kubectl

```bash
$(terraform output -raw configure_kubectl)
```

This runs `aws eks update-kubeconfig` with the correct cluster name and region.

## Post-deploy validation

Run these commands to confirm the cluster is healthy:

```bash
# Cluster reachable
kubectl cluster-info

# No nodes yet (Auto Mode provisions on demand)
kubectl get nodes

# NodePools ready
kubectl get nodepools

# NodeClasses present
kubectl get nodeclasses

# StorageClass exists with correct provisioner
kubectl get sc -o custom-columns='NAME:.metadata.name,PROVISIONER:.provisioner'
# Expected: provisioner = ebs.csi.eks.amazonaws.com

# IngressClass present
kubectl get ingressclass

# Karpenter CRDs installed
kubectl api-resources | grep karpenter
```

If any of these fail, check `terraform output` for errors and verify your AWS
credentials are active.

## Deploying examples

Each example is a self-contained directory under `examples/`. Most are pure
kubectl-apply; some require Terraform (KEDA in pod-autoscaling).

### kubectl-based examples

```bash
kubectl apply -f examples/graviton/
kubectl apply -f examples/spot/
kubectl apply -f examples/gpu/
kubectl apply -f examples/neuron/
kubectl apply -f examples/cost-optimization/
kubectl apply -f examples/capacity-reservation/
kubectl apply -f examples/static-capacity/
kubectl apply -f examples/batch-jobs/
kubectl apply -f examples/disruption-budgets/
```

After applying, watch pods:

```bash
kubectl get pods -A -w
```

A node provisions within 60-90 seconds, and the pod starts shortly after.

### Terraform-based examples

The pod-autoscaling example (KEDA) has its own Terraform root:

```bash
cd examples/pod-autoscaling/terraform && terraform init && terraform apply -auto-approve
```

### Example purposes

| Example | Demonstrates |
|---------|-------------|
| graviton | ARM64 scheduling, nodeSelector for architecture |
| spot | Spot capacity type, diverse instance families for availability |
| gpu | GPU nodeSelector, NVIDIA device plugin (managed), tolerations |
| neuron | Inferentia2 scheduling, neuron device plugin, vLLM serving |
| cost-optimization | Weighted NodePool priority, pause-pod overprovision buffer |
| capacity-reservation | ODCR targeting via NodePool requirements |
| static-capacity | `spec.replicas` for fixed fleet, consolidation immunity |
| batch-jobs | `karpenter.sh/do-not-disrupt` annotation, dedicated pool |
| disruption-budgets | `spec.disruption.budgets` configuration patterns |
| pod-autoscaling | HPA (CPU) + KEDA (SQS queue depth) scaling |
| observability | Container Insights addon, log groups, Application Signals |

## Optional features

### Public HTTPS exposure (base_domain)

Setting `base_domain` enables:
- ACM wildcard certificate for `*.<subdomain>.<base_domain>`
- external-dns installation with Pod Identity
- Internet-facing ALB (shared across examples)
- Automatic DNS record creation for each Ingress host

```bash
terraform apply -var='base_domain=example.com' -var='subdomain=automode'
```

The hosted zone must already exist. Terraform does not create it.

### Observability (Container Insights)

```bash
terraform apply -var='enable_observability=true'
```

Installs the CloudWatch Observability EKS addon. Provides:
- Container-level CPU, memory, network metrics
- Pod log forwarding to CloudWatch Logs
- Application Signals distributed tracing

Incurs CloudWatch costs proportional to cluster size and log volume.

### Ephemeral storage encryption

```bash
terraform apply -var='ephemeral_storage_kms_key_id=arn:aws:kms:us-west-2:123456789012:key/abc-123'
```

Encrypts the root EBS volume on every Auto Mode node with your KMS key.

## Cleanup procedure

Use the included cleanup script for safe teardown. It drains K8s-managed AWS
resources before destroying Terraform state, then sweeps for orphans.

```bash
# Preview what would be deleted
./scripts/cleanup.sh --dry-run

# Full non-interactive teardown
./scripts/cleanup.sh --yes

# Keep storage (PVCs/EBS volumes preserved)
./scripts/cleanup.sh --yes --keep-storage

# Orphan sweep only (Terraform already destroyed)
./scripts/cleanup.sh --skip-terraform --cluster-name <name> --region <region>
```

Do not run bare `terraform destroy` alone. It leaves orphaned ALBs, EBS volumes,
ENIs, and security groups created by in-cluster controllers. The cleanup script
handles these properly.

Full teardown reference: `claude-md/CLEANUP.md` in this repository.

## Sources

- [EKS Auto Mode overview](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Auto Mode reference](https://docs.aws.amazon.com/eks/latest/userguide/auto-reference.html)
- [Configure ALB](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html)
- [Configure NLB](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-nlb.html)
- [Create StorageClass](https://docs.aws.amazon.com/eks/latest/userguide/create-storage-class.html)
- [Tag subnets for Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/tag-subnets-auto.html)
- [Static capacity](https://docs.aws.amazon.com/eks/latest/userguide/auto-static-capacity.html)
- [Migrate to Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/migrate-auto.html)
- [Best practices for Auto Mode](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html)
- [This repository](https://github.com/aws-samples/sample-aws-eks-auto-mode)
