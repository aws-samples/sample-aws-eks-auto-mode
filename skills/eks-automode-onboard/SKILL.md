---
name: eks-automode-onboard
description: >
  Onboarding guide for EKS Auto Mode newcomers. Use this skill when the user asks
  about EKS Auto Mode concepts, wants to deploy their first Auto Mode cluster using
  this repo, needs help picking an example, or hits common first-day issues. Trigger
  phrases: "what is Auto Mode", "how do I deploy", "which example should I use",
  "getting started with EKS Auto Mode", "first cluster", "deploy this repo",
  "Auto Mode tutorial", "newbie", "onboard", "walkthrough".
---

# EKS Auto Mode Onboarding

Help users go from zero to a running EKS Auto Mode cluster using this repository.
Cover concepts, deployment, example selection, and first-encounter troubleshooting.

## What EKS Auto Mode manages for you

EKS Auto Mode runs these components inside the AWS-managed control plane so you never
install, configure, or upgrade them:

| Component | What it does |
|-----------|--------------|
| Karpenter | Provisions, scales, and consolidates EC2 compute |
| VPC CNI | Pod networking, IP allocation, security groups |
| EBS CSI driver | Persistent volume provisioning from PVCs |
| ALB controller | Creates ALBs/NLBs from Ingress and Service resources |
| CoreDNS | Cluster DNS (runs as a node-level service, not pods) |
| Pod Identity Agent | Fine-grained IAM for pods without manual IRSA |
| Node health monitor | Detects and replaces unhealthy nodes |
| AMI lifecycle | Picks correct AMI, patches weekly, remediates drift |

You interact via standard K8s APIs (NodePool, NodeClass, Ingress, StorageClass).
AWS handles the operational lifecycle behind those APIs.

## Which example should I use?

| Use case | Example directory | What it deploys |
|----------|-------------------|-----------------|
| First deployment / validation | `examples/graviton/` | 2048 game on ARM64 Graviton |
| Fault-tolerant batch / dev | `examples/spot/` | 2048 game on Spot instances |
| ML inference (NVIDIA GPU) | `examples/gpu/` | Qwen 3 on GPU |
| ML inference (Inferentia2) | `examples/neuron/` | DeepSeek-R1-Qwen3-8B via vLLM |
| OD + Spot mix with headroom | `examples/cost-optimization/` | Weighted priority pools + pause-pod |
| Pin to reserved capacity | `examples/capacity-reservation/` | ODCR-targeted NodePool |
| Fixed always-on fleet | `examples/static-capacity/` | `spec.replicas` nodes, no consolidation |
| Protect long-running jobs | `examples/batch-jobs/` | `do-not-disrupt` annotation pattern |
| Limit drain concurrency | `examples/disruption-budgets/` | NodePool disruption budget config |
| CPU autoscaling + SQS-driven | `examples/pod-autoscaling/` | HPA + KEDA ScaledObjects |
| Metrics, logs, tracing | `examples/observability/` | CloudWatch Container Insights |

Start with `examples/graviton/` if you just want to validate the cluster works.

## Deployment steps

### 1. Clone

```bash
git clone https://github.com/aws-samples/sample-aws-eks-auto-mode.git && cd sample-aws-eks-auto-mode
```

### 2. Configure variables

Edit `terraform/terraform.tfvars` (or pass `-var` flags). The important variables:

| Variable | Purpose | Default |
|----------|---------|---------|
| `name` | Cluster and VPC name | `automode-cluster` |
| `region` | AWS region | `us-west-2` |
| `eks_cluster_version` | K8s version (minimum 1.29 for Auto Mode) | `1.34` |
| `tags` | Tags applied everywhere via 5-layer pattern | `{"auto-delete"="never"}` |
| `base_domain` | Route53 zone for public HTTPS (leave empty for internal-only) | `""` |
| `enable_observability` | CloudWatch Container Insights | `false` |

### 3. Deploy

```bash
cd terraform && terraform init && terraform apply -auto-approve
```

Terraform creates the VPC, EKS cluster, IAM roles, NodePools, NodeClasses,
StorageClasses, and IngressClasses. Takes 12-18 minutes.

### 4. Configure kubectl

```bash
$(terraform output -raw configure_kubectl)
```

### 5. Validate

```bash
kubectl get nodes                   # Should show zero nodes (no workloads yet)
kubectl get nodepools               # Shows general-purpose + any custom pools
kubectl get nodeclasses             # Shows default + any custom classes
kubectl get storageclass            # Should list ebs-csi class
kubectl get ingressclass            # Should list alb class
```

### 6. Deploy an example

```bash
kubectl apply -f examples/graviton/
kubectl get pods -n game-2048 -w    # Watch Auto Mode provision a Graviton node
```

A node appears within 60-90 seconds. The pod transitions to Running once the node
joins and passes readiness checks.

## Key concepts

### What you manage vs what AWS manages

| You manage | AWS manages |
|------------|-------------|
| NodePool specs (instance families, AZs, taints) | Actual instance launches + termination |
| NodeClass specs (tags, storage config) | AMI selection, patching, drift remediation |
| Ingress / Service manifests | ALB/NLB creation, TLS termination, target registration |
| PVC manifests + StorageClass | EBS volume provisioning, attach, detach |
| Pod specs and scheduling constraints | Node health monitoring + auto-repair |
| Cluster version upgrades (EKS console/API) | Component version upgrades (Karpenter, CNI, CSI, CoreDNS) |

### NodePool and NodeClass relationship

```
NodePool (what to launch)         NodeClass (how to launch)
- instance families               - subnet discovery rules
- architectures (amd64/arm64)     - security group discovery
- capacity types (on-demand/spot) - ephemeral storage config
- taints and labels               - tags pushed to EC2/EBS/ENI
- disruption settings             - IMDS settings
- weight (priority)               - KMS key for storage
        |                                  |
        +---- nodeClassRef.name -----------+
```

A NodePool references exactly one NodeClass. Multiple NodePools can share a NodeClass.

The `default` NodePool and `default` NodeClass are AWS-managed. Do not edit the
`default` NodeClass (changes revert silently within minutes). Create custom
NodeClasses for durable customization.

### Templatefile rendering chain

This repo uses Terraform's `templatefile()` to render K8s manifests:

```
nodepool-templates/*.yaml.tpl  (source templates)
       |
       v  terraform apply (templatefile + local_file)
       |
nodepools/*.yaml  (rendered manifests applied by kubectl_manifest)
```

If you edit a `.tpl` file, the rendered YAML does not update until you run
`terraform apply`. Never edit the rendered YAML directly; it will be overwritten.

## Common gotchas for newcomers

1. **Pods stuck Pending** -- check `nodeSelector` and `node.kubernetes.io/instance-type`
   labels. Auto Mode only provisions nodes that match a NodePool. If no pool matches
   your pod's constraints, it stays Pending forever.

2. **EBS StorageClass provisioner name** -- use `ebs.csi.eks.amazonaws.com`, NOT
   `ebs.csi.aws.com`. The latter is the self-managed driver. Auto Mode uses a
   different provisioner name.

3. **Editing the default NodeClass** -- your changes revert silently. Always create
   a named custom NodeClass.

4. **Tags not landing on resources** -- you need the IAM custom-tags policy
   (`enable_auto_mode_custom_tags=true` in the module). Without it, any custom tag
   key outside `eks:*`, `kubernetes.io/*`, `karpenter.sh/*` is silently denied.

5. **No SSH/SSM access to nodes** -- nodes are Bottlerocket and read-only. Use
   `kubectl debug node/<name>` or the NodeDiagnostic resource for troubleshooting.

6. **Rendered YAML stale after template edit** -- run `terraform apply` to
   re-render. Applying stale YAML silently reverts your fix.

7. **LB not provisioning** -- subnets need `kubernetes.io/role/elb: "1"` (public)
   or `kubernetes.io/role/internal-elb: "1"` (private) tags. This repo adds them
   automatically, but custom VPCs may not.

## When to use the detailed references

- **Concepts deep-dive** (managed components, instance families, IMDS, disruption model):
  see `references/concepts.md`
- **Full deployment walkthrough** (prerequisites, variable reference, post-deploy validation,
  cleanup): see `references/deployment-guide.md`
- **Troubleshooting** (Pending pods, node join failures, tag issues, LB problems,
  storage errors): see `references/troubleshooting.md`
- **Tagging patterns** (5-layer model, IAM policy, known gaps): see `claude-md/TAGGING.md`
- **Cleanup/teardown** (drain order, orphan sweep, post-destroy verification):
  see `claude-md/CLEANUP.md`

## Sources

- [EKS Auto Mode overview](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Auto Mode reference](https://docs.aws.amazon.com/eks/latest/userguide/auto-reference.html)
- [Instance types in Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode-learn-instances.html)
- [Create a NodePool](https://docs.aws.amazon.com/eks/latest/userguide/create-node-pool.html)
- [Create a NodeClass](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html)
- [Configure ALB](https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html)
- [Create StorageClass](https://docs.aws.amazon.com/eks/latest/userguide/create-storage-class.html)
- [Troubleshooting Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/auto-troubleshoot.html)
- [Best practices for Auto Mode](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html)
- [This repository](https://github.com/aws-samples/sample-aws-eks-auto-mode)
