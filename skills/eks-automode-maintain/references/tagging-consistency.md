# Tagging Consistency — 5-Layer Verification Guide

This reference covers how to verify all 5 tagging layers are aligned and
debug when tags fail to land on AWS resources.

---

## Layer-by-layer verification

### Layer 1: Provider default_tags

**File:** `terraform/main.tf`

```hcl
provider "aws" {
  default_tags {
    tags = var.tags
  }
}
```

**What it tags:** All resources created directly by Terraform — VPC, subnets,
NAT gateway, IAM roles, KMS keys, S3 buckets, Lambda functions, ACM certs,
Route53 records (where supported), EKS cluster resource itself.

**What it does NOT tag:**
- EC2 instances launched by Karpenter/Auto Mode
- EBS volumes created by the EBS CSI driver (PVC-provisioned)
- ENIs created by the VPC CNI
- ALBs/NLBs created by the ALB controller
- Target groups, listeners, listener rules
- Security groups created by the ALB controller or EKS networking
- EKS primary security group (use `cluster_tags` instead)
- EFS access points created by the EFS CSI driver

**Verify:**
```bash
# Pick any TF-created resource and check tags
aws ec2 describe-vpcs --filters "Name=tag:Blueprint,Values=$CLUSTER" \
  --query 'Vpcs[].Tags'
```

---

### Layer 2: EKS cluster_tags

**File:** `terraform/eks.tf`

```hcl
module "eks" {
  ...
  cluster_tags = local.tags
}
```

**What it tags:** The EKS-managed primary security group. This SG is created by
the EKS service (not Terraform), so `default_tags` cannot reach it. The module
uses `aws_ec2_tag` resources internally.

**Verify:**
```bash
# Get the primary SG ID
PRIMARY_SG=$(aws eks describe-cluster --name $CLUSTER \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

aws ec2 describe-tags --filters "Name=resource-id,Values=$PRIMARY_SG" \
  --query 'Tags[?Key!=`aws:eks:cluster-name`]'
```

**Gotcha:** Pass tags as `cluster_tags`, not `tags`. The `tags` input on the
module goes to the cluster resource itself (which `default_tags` already
covers). `cluster_tags` specifically targets the primary SG via `aws_ec2_tag`.

---

### Layer 3: NodeClass spec.tags

**Files:** `nodepool-templates/*.yaml.tpl`

Each template includes:
```yaml
spec:
  tags:
    ${indent(4, yamlencode(tags))}
```

**What it tags:** EC2 instances, root EBS volumes, and ENIs launched by Auto
Mode's built-in Karpenter for that NodeClass.

**Verify:**
```bash
# Check running instances
aws ec2 describe-instances \
  --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`auto-delete`].Value|[0]]' \
  --output table
```

**Gotchas:**
- Never patch the managed `default` NodeClass — EKS silently reverts custom
  fields within minutes. Always use a named custom NodeClass.
- NodePools must reference the custom NodeClass via `spec.template.spec.nodeClassRef.name`.
- Tags only apply to instances launched AFTER the NodeClass is applied. Existing
  nodes keep their original tags.

**All templates must include spec.tags.** Verify coverage:
```bash
# Count templates vs templates with spec.tags (should match)
ls nodepool-templates/*.yaml.tpl | wc -l
grep -l 'spec.tags' nodepool-templates/*.yaml.tpl | wc -l
```

---

### Layer 4: StorageClass tagSpecification

**File:** `terraform/tagging.tf`

```hcl
parameters = merge(
  { type = "gp3" },
  { for i, k in keys(local.tags) : "tagSpecification_${i + 1}" => "${k}=${local.tags[k]}" },
)
```

**What it tags:** EBS volumes created by PVCs that use the `ebs` StorageClass
(set as default). Volumes from the managed `auto-ebs-sc` class remain untagged
(managed StorageClass cannot be mutated).

**Verify:**
```bash
# Check PVC-created volumes
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/created-by,Values=ebs.csi.eks.amazonaws.com" \
  --query 'Volumes[].[VolumeId,Tags[?Key==`auto-delete`].Value|[0]]' \
  --output table
```

**Gotchas:**
- StorageClass `parameters` are **immutable**. `kubectl apply` on a changed
  StorageClass errors. You must `kubectl delete storageclass ebs` then recreate.
  Terraform handles this with `kubectl_manifest` force behavior.
- Existing PVCs/volumes keep their original tags. Only new PVCs get updated tags.
- The legacy `gp2` StorageClass is deleted by `null_resource.delete_gp2_storageclass`
  so PVCs without an explicit `storageClassName` land on the tagged `ebs` class.

---

### Layer 5: IngressClassParams spec.tags

**File:** `terraform/ingressclass.tf`

```yaml
spec:
  tags:
    - key: auto-delete
      value: never
```

(Rendered dynamically from `local.tags` via `ingressclass_tags_yaml` local.)

**What it tags:** ALBs, target groups, listeners, and listener-rule security
groups created by Auto Mode's built-in ALB controller for Ingresses using the
`alb` IngressClass.

**Verify:**
```bash
# List ALBs and their tags
for arn in $(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[].LoadBalancerArn' --output text); do
  echo "=== $arn ==="
  aws elbv2 describe-tags --resource-arns $arn --query 'TagDescriptions[].Tags'
done
```

**Gotchas:**
- IngressClassParams is per-class. If you have multiple IngressClasses (e.g.
  internal + internet-facing), each needs its own IngressClassParams with tags.
- This file has two mutually-exclusive branches gated on `local.enable_domain`.
  Both branches include `spec.tags`.

---

## IAM requirement: enable_auto_mode_custom_tags

Layers 3-5 call AWS APIs under the cluster IAM role. The managed policies only
allow `eks:*`, `kubernetes.io/*`, `karpenter.sh/*` tag keys by default. Custom
keys (like `auto-delete`) are DENIED without an additional IAM policy.

**Fix:** `enable_auto_mode_custom_tags = true` on the EKS module (default since
v20.31). Verify in `terraform/eks.tf`:

```bash
grep 'enable_auto_mode_custom_tags' terraform/eks.tf
```

If this is `false` or missing, Layers 3-5 silently fail — resources create
successfully but without your custom tags.

---

## Known gap: LoadBalancer-type Services

There is no cluster-wide default for LoadBalancer-type Service tags. Each
Service manifest must carry the annotation:

```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags: "auto-delete=never"
```

This is documented in `claude-md/TAGGING.md`. Remind contributors to add this
annotation when creating LoadBalancer Services in examples.

---

## Debugging: tag not landing?

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| New EC2 instances untagged | IAM policy missing | Verify `enable_auto_mode_custom_tags = true` |
| EC2 tagged but old ones not | Tags are create-time only | Retag with `aws ec2 create-tags` |
| NodeClass tags revert | Patched managed `default` NodeClass | Use custom NodeClass; delete any patches |
| StorageClass change rejected | Parameters immutable | Delete and recreate StorageClass |
| CloudTrail shows `UnauthorizedOperation` | IAM allowlist doesn't include your key | Check custom tag IAM policy attachment |
| ALB missing tags | Wrong IngressClass or IngressClassParams | Verify Ingress specifies `ingressClassName: alb` |
| Primary SG untagged | Using `tags` instead of `cluster_tags` | Pass via `cluster_tags` on module block |

**CloudTrail query for tag failures:**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=RunInstances \
  --query 'Events[?contains(CloudTrailEvent, `UnauthorizedOperation`)].CloudTrailEvent' \
  --max-results 5 --output text | jq -r '.errorMessage' 2>/dev/null
```

---

## Adding a new tag key

When adding a tag key across the repo:

1. Add to `var.tags` default in `variables.tf` (or instruct users to pass it).
2. Run `terraform apply` — this propagates through all 5 layers automatically
   because they all source from `local.tags`.
3. Verify with the per-layer commands above.
4. Update `claude-md/TAGGING.md` if the new key has special semantics.
5. Existing resources remain untagged — retag imperatively if needed.

---

## Sources

- [Tag propagation IAM policy](https://docs.aws.amazon.com/eks/latest/userguide/auto-cluster-iam-role.html#tag-prop)
- [Custom NodeClass creation](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html)
- [EKS Auto Mode best practices](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html)
- [This repo (sample-aws-eks-auto-mode)](https://github.com/aws-samples/sample-aws-eks-auto-mode)
- Internal: `claude-md/TAGGING.md`, `terraform/tagging.tf`, `terraform/ingressclass.tf`, `terraform/eks.tf`
