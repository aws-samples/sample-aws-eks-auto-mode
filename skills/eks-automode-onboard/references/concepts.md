# EKS Auto Mode -- Concepts

## What Auto Mode manages

EKS Auto Mode runs the following as managed control-plane components. You do not
install, configure, upgrade, or monitor any of them directly:

| Component | Responsibility |
|-----------|---------------|
| Karpenter | Compute provisioning, scaling, consolidation, drift remediation |
| VPC CNI | Pod networking, IP address management, security group enforcement |
| EBS CSI driver | PersistentVolume provisioning and lifecycle (provisioner: `ebs.csi.eks.amazonaws.com`) |
| ALB controller | Application and Network Load Balancer creation from Ingress/Service |
| CoreDNS | Cluster DNS resolution (runs as node-level service, not user-visible pods) |
| Pod Identity Agent | IAM credential injection for pods (replaces manual IRSA setup) |
| kube-proxy | Per-node network rules for Service routing |
| Node monitoring | Health checks, automatic repair/replacement of failed nodes |

All components receive automatic version upgrades independent of your cluster version.
You never see a Helm release or DaemonSet for these.

## Shared responsibility model

| AWS manages | You manage |
|-------------|------------|
| Component installation and upgrades | Cluster version (initiate upgrade via console/API) |
| AMI selection, patching (~weekly) | NodePool definitions (what to launch) |
| Node health and replacement | NodeClass customization (how to launch) |
| Instance termination for drift/expiry | Workload scheduling constraints |
| Load balancer provisioning | Ingress/Service manifests |
| Volume provisioning and attach | PVC definitions and StorageClass selection |
| DNS resolution (CoreDNS) | Application-level DNS (external-dns is opt-in) |
| Security patching | IAM roles and policies for your workloads |

## NodePool vs NodeClass

### NodePool (what to launch)

Defines compute constraints that Karpenter uses to select instances:

- `spec.template.spec.requirements` -- instance families, architectures (amd64/arm64),
  capacity types (on-demand/spot), availability zones
- `spec.template.metadata.labels` -- labels applied to every node from this pool
- `spec.template.spec.taints` -- taints applied to nodes
- `spec.disruption` -- consolidation policy, budgets, expireAfter
- `spec.weight` -- priority when multiple pools match (higher wins)
- `spec.limits` -- resource ceilings (CPU, memory)

### NodeClass (how to launch)

Defines the infrastructure blueprint for the EC2 instance:

- `spec.subnetSelectorTerms` -- discover subnets by tags
- `spec.securityGroupSelectorTerms` -- discover security groups by tags
- `spec.tags` -- tags pushed to EC2 instances, root EBS volumes, and ENIs
- `spec.ephemeral` -- ephemeral storage configuration (size, IOPS, throughput, encryption)
- `spec.role` -- IAM role for the node (usually the cluster node role)

API version: `eks.amazonaws.com/v1`

### Default vs custom

EKS creates a managed `default` NodePool and `default` NodeClass. These cover
general-purpose workloads out of the box. Key rules:

- The `default` NodeClass is reconciled by EKS. Edits revert silently within minutes.
- Create a named custom NodeClass for any durable customization (tags, storage, etc.).
- Custom NodePools must set `spec.template.spec.nodeClassRef.name` to your custom
  NodeClass (or the `default` if no customization is needed).
- The `default` NodePool can be reconfigured via `set-builtin-node-pools` API or
  by applying a NodePool manifest with `metadata.name: general-purpose`.

## 5-layer tagging pattern

Tags reach different resource types through different mechanisms. A single
`provider { default_tags {} }` is insufficient. The 5 layers:

1. **Provider `default_tags`** -- Terraform-direct resources (VPC, subnets, IAM, KMS)
2. **`cluster_tags`** -- EKS primary security group (via `aws_ec2_tag`)
3. **NodeClass `spec.tags`** -- EC2 instances, root EBS, ENIs launched by Karpenter
4. **StorageClass `tagSpecification`** -- EBS volumes from PVCs
5. **IngressClassParams `spec.tags`** -- ALBs, target groups, listeners, SGs

Each layer requires its own configuration. The IAM custom-tags policy
(`enable_auto_mode_custom_tags=true`) is load-bearing for layers 3-5; without it,
custom tag keys are silently denied.

Full reference: `claude-md/TAGGING.md` in this repository.

## Instance families supported

Auto Mode supports a broad set of instance families:

- **General purpose**: M5, M5a, M5ad, M5d, M5n, M6a, M6g, M6gd, M6i, M6id, M6in, M7a, M7g, M7gd, M7i, M7i-flex, M8g
- **Compute optimized**: C5, C5a, C5ad, C5d, C5n, C6a, C6g, C6gd, C6gn, C6i, C6id, C6in, C7a, C7g, C7gd, C7gn, C7i, C7i-flex, C8g
- **Memory optimized**: R5, R5a, R5ad, R5b, R5d, R5n, R6a, R6g, R6gd, R6i, R6id, R6in, R7a, R7g, R7gd, R7i, R7iz, R8g
- **Accelerated (GPU)**: G5, G6, G6e, Gr6, P4d, P4de, P5, P5e
- **Accelerated (Inferentia/Trainium)**: Inf2, Trn1, Trn1n, Trn2
- **Storage optimized**: I3, I3en, I4g, I4i, Im4gn, Is4gen
- **HPC**: Hpc6a, Hpc6id, Hpc7a, Hpc7g

Availability varies by region. NodePool `requirements` filter to your desired subset.

## Ephemeral storage and NVMe behavior

- Every Auto Mode node has an EBS root volume for ephemeral storage (OS, container
  images, emptyDir volumes).
- Instance types with local NVMe (d-suffix families like M6gd, C6id) expose NVMe as
  additional ephemeral storage automatically.
- Default root volume: 80 GiB gp3. Configurable via NodeClass `spec.ephemeral`.
- Ephemeral storage is encrypted. Use `ephemeral_storage_kms_key_id` variable for
  custom KMS keys.
- emptyDir volumes consume ephemeral storage. Large emptyDirs can cause node pressure.

## IMDS restrictions

- IMDSv2 is enforced (IMDSv1 disabled).
- Hop limit is 1 (only the node itself can reach IMDS; containers cannot by default).
- Pods use Pod Identity for AWS credentials, not instance metadata.
- If a workload genuinely needs IMDS access, it requires a hostNetwork pod (not
  recommended; use Pod Identity instead).

## What is NOT supported

- **SSH access** -- nodes are Bottlerocket, read-only filesystem, no SSH daemon
- **SSM Session Manager** -- not installed on Auto Mode nodes
- **Custom AMIs** -- you cannot specify your own AMI; AWS selects and patches
- **Windows nodes** -- Auto Mode is Linux (Bottlerocket) only
- **DaemonSets for managed components** -- they run in the control plane, not on nodes
- **Instance store as PV** -- local NVMe is ephemeral only, not usable for PVCs
- **More than 110 pods per node** -- hard limit from the kubelet configuration

## Key labels

Auto Mode nodes carry these labels (non-exhaustive):

| Label | Values | Purpose |
|-------|--------|---------|
| `eks.amazonaws.com/compute-type` | `auto` | Identifies Auto Mode nodes |
| `node.kubernetes.io/instance-type` | e.g., `m6g.xlarge` | Standard K8s label |
| `topology.kubernetes.io/zone` | e.g., `us-west-2a` | AZ placement |
| `kubernetes.io/arch` | `amd64`, `arm64` | CPU architecture |
| `kubernetes.io/os` | `linux` | OS (always linux) |
| `karpenter.sh/capacity-type` | `on-demand`, `spot` | Capacity type |
| `karpenter.sh/nodepool` | pool name | Which NodePool launched this node |
| `eks.amazonaws.com/nodeclass` | class name | Which NodeClass was used |

Use `eks.amazonaws.com/compute-type: auto` in nodeSelector or affinity to target
Auto Mode nodes specifically (useful during migration from Standard Mode).

## Disruption model

Auto Mode's Karpenter continuously optimizes the fleet. Four disruption reasons:

### Consolidation

Removes underutilized nodes or replaces them with cheaper/smaller instances.
Respects PodDisruptionBudgets and `do-not-disrupt` annotations.

### Drift

When a NodePool or NodeClass spec changes, existing nodes no longer match. Karpenter
drains and replaces them. Also triggers when AWS updates the AMI.

### Expiration

Nodes have a maximum lifetime (`spec.disruption.expireAfter`). Default: 336h (14 days).
After expiry, nodes are cordoned and drained. Prevents configuration drift.

### Disruption budgets

`spec.disruption.budgets` controls how many nodes can be disrupted simultaneously:

```yaml
spec:
  disruption:
    budgets:
      - nodes: "10%"     # Max 10% of pool disrupted at once
      - nodes: "0"       # During this schedule, no disruption
        schedule: "0 9 * * 1-5"  # Weekdays 9 AM
        duration: 8h             # For 8 hours
```

Budgets protect availability during maintenance. Set `nodes: "0"` during business
hours if needed.

## Sources

- [EKS Auto Mode overview](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Auto Mode reference](https://docs.aws.amazon.com/eks/latest/userguide/auto-reference.html)
- [Instance types in Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode-learn-instances.html)
- [Auto Mode IAM](https://docs.aws.amazon.com/eks/latest/userguide/auto-learn-iam.html)
- [Auto Mode networking](https://docs.aws.amazon.com/eks/latest/userguide/auto-networking.html)
- [Create a NodePool](https://docs.aws.amazon.com/eks/latest/userguide/create-node-pool.html)
- [Create a NodeClass](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html)
- [Set built-in NodePools](https://docs.aws.amazon.com/eks/latest/userguide/set-builtin-node-pools.html)
- [On-Demand Capacity Reservations](https://docs.aws.amazon.com/eks/latest/userguide/auto-odcr.html)
- [Migrate to Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/migrate-auto.html)
- [Best practices for Auto Mode](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html)
- [This repository](https://github.com/aws-samples/sample-aws-eks-auto-mode)
