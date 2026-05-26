---
name: eks-automode-maintain
description: "Repo maintenance for sample-aws-eks-auto-mode. Keeps docs, templates, rendered YAML, and tagging layers in sync. Use when updating nodepool templates, terraform config, examples, tagging, cleanup scripts, or docs. Triggers: maintain, docs sync, tagging update, template change, rendered yaml, file relationships, PR checklist, keep in sync."
---

# EKS Auto Mode — Maintainer Skill

You maintain `sample-aws-eks-auto-mode`. This skill tells you what else to
update when you change a file, how the rendering chain works, and how to verify
the 5-layer tagging pattern stays consistent.

For the full file map, tagging deep-dive, or docs-sync rules, see `references/`.

---

## The rendering chain

NodePool and example YAML in this repo are template-rendered, not hand-written.
Understanding this chain prevents the most common maintainer mistake: editing a
`.tpl` without re-rendering.

```
nodepool-templates/*.yaml.tpl        (source of truth)
         │
         ▼
terraform/setup.tf                   (templatefile() calls with variables)
         │
         ▼
nodepools/*.yaml                     (rendered output, gitignored)
examples/*/rendered.yaml             (some example YAMLs are also rendered)
```

**Variable flow:**

1. `terraform/variables.tf` defines `var.tags`, `var.name`, `var.base_domain`, etc.
2. `terraform/main.tf` merges into `local.tags` and `local.full_domain`.
3. `terraform/setup.tf` passes `local.tags`, `module.eks.cluster_name`, `module.eks.node_iam_role_name`, and `var.ephemeral_storage_kms_key_id` into each `templatefile()` call.
4. `local_file` resources write the rendered YAML to `nodepools/` or `examples/*/`.

**The gotcha:** Editing a `.tpl` file fixes the template but the cluster still
runs the previously-rendered YAML. You must run `terraform apply` to re-render.
Running `kubectl apply -f nodepools/` on stale rendered YAML silently reverts
your fix.

---

## Decision matrix: I changed X, what else needs updating?

| Changed | Also update |
|---------|-------------|
| `nodepool-templates/*.yaml.tpl` | Run `terraform apply` to re-render; verify rendered output in `nodepools/` |
| `terraform/variables.tf` (new var) | `setup.tf` (pass to `templatefile`); README variable reference table |
| `terraform/eks.tf` | `claude-md/TAGGING.md` if tag-related; README if feature-facing |
| `examples/*` (new example dir) | README examples table; `misc/website` sidebar; `setup.tf` if `.tpl` needed |
| `terraform/tagging.tf` | `claude-md/TAGGING.md` (keep in sync); verify all 5 layers still covered |
| `scripts/cleanup.sh` | `claude-md/CLEANUP.md` flags/usage section |
| Any observability change | `examples/observability/README.md`; `terraform/observability.tf` |
| `terraform/versions.tf` | README prerequisites section (provider version badges) |
| `terraform/ingressclass.tf` | `claude-md/TAGGING.md` Layer 5 section |
| `terraform/alb-acm.tf` | README domain/DNS section; example Ingress `.tpl` files if host changes |
| `terraform/setup.tf` (new `local_file`) | `.gitignore` (add rendered output path); README if user-facing |

---

## 5-layer tagging consistency

Every resource the cluster creates should carry your tags. The 5 layers are:

| # | Layer | File | What it tags |
|---|-------|------|--------------|
| 1 | Provider `default_tags` | `terraform/main.tf` | All TF-direct resources (VPC, subnets, IAM, KMS, etc.) |
| 2 | `cluster_tags` | `terraform/eks.tf` | EKS primary security group (unreachable by `default_tags`) |
| 3 | NodeClass `spec.tags` | `nodepool-templates/*.yaml.tpl` | EC2 instances, root EBS, ENIs from Auto Mode |
| 4 | StorageClass `tagSpecification` | `terraform/tagging.tf` | PVC-provisioned EBS volumes |
| 5 | IngressClassParams `spec.tags` | `terraform/ingressclass.tf` | ALBs, target groups, listeners |

**Verification checklist (run after any tag change):**

```bash
# Layer 1: provider default_tags
grep -A5 'default_tags' terraform/main.tf

# Layer 2: cluster_tags passed to module
grep 'cluster_tags' terraform/eks.tf

# Layer 3: spec.tags in every .tpl
grep -l 'spec.tags' nodepool-templates/*.yaml.tpl | wc -l  # should match template count

# Layer 4: tagSpecification in StorageClass
grep 'tagSpecification' terraform/tagging.tf

# Layer 5: spec.tags in IngressClassParams
grep -A2 'spec:' terraform/ingressclass.tf | grep 'tags'
```

**Confirm tags are actually landing on AWS resources:**

```bash
# EC2 instances (Layer 3)
aws ec2 describe-instances --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER" \
  --query 'Reservations[].Instances[].Tags'

# EBS volumes (Layer 4)
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/$CLUSTER,Values=owned" \
  --query 'Volumes[].Tags'

# ALBs (Layer 5)
aws elbv2 describe-tags --resource-arns $(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[].LoadBalancerArn' --output text)
```

**IAM requirement:** Layers 3-5 fail silently without `enable_auto_mode_custom_tags = true`
on the EKS module (default since v20.31). Check `terraform/eks.tf`.

---

## When to update TAGGING.md vs CLEANUP.md

| Update `claude-md/TAGGING.md` when... | Update `claude-md/CLEANUP.md` when... |
|----------------------------------------|----------------------------------------|
| Adding/removing a tagging layer | Adding a new resource type that might orphan |
| Changing tag keys or values | Changing `scripts/cleanup.sh` flags |
| Updating IAM policy for tags | Discovering a new cleanup ordering dependency |
| Fixing a "tag not landing" debug path | Adding a verification command |
| Documenting a new `default_tags` gap | Updating the drain-before-destroy order |

Both files are gitignored (`claude-md/` in `.gitignore`) because they are
maintainer-internal docs generated for Claude context. They do not ship to
end-users but they keep institutional knowledge alive across sessions.

---

## PR checklist for maintainers

Before merging, verify:

- [ ] Every `.tpl` change has a matching `terraform apply` validation (CI or local)
- [ ] New variables appear in README's Configuration section
- [ ] Tag-related changes are reflected in `claude-md/TAGGING.md`
- [ ] Cleanup-related changes are reflected in `claude-md/CLEANUP.md`
- [ ] New examples have their own `README.md` with prerequisites and commands
- [ ] Rendered YAML paths added to `.gitignore` if generated by `setup.tf`
- [ ] `SECURITY_CONSIDERATIONS.md` updated if security posture changed
- [ ] No hardcoded cluster names or account IDs in committed files
- [ ] Example READMEs use relative paths (no absolute filesystem paths)
- [ ] Observe commands separated into `examples/observability/` not inline

---

## When to reference the detailed docs

| You need... | Go to... |
|-------------|----------|
| Complete file map and dependency graph | `references/file-relationships.md` |
| Full 5-layer tagging with debug commands | `references/tagging-consistency.md` |
| Docs update rules and PR template | `references/docs-sync-checklist.md` |
| Upstream AWS docs on Auto Mode | Links in Sources below |

---

## Sources

- [EKS Auto Mode user guide](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Auto Mode IAM roles](https://docs.aws.amazon.com/eks/latest/userguide/auto-learn-iam.html)
- [Custom NodeClass creation](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html)
- [Tag propagation IAM policy](https://docs.aws.amazon.com/eks/latest/userguide/auto-cluster-iam-role.html#tag-prop)
- [EKS Auto Mode best practices](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html)
- [This repo (sample-aws-eks-auto-mode)](https://github.com/aws-samples/sample-aws-eks-auto-mode)
- [Skill format reference](https://github.com/anthropics/skills/tree/main/skills/skill-creator)
- Internal: `claude-md/TAGGING.md`, `claude-md/CLEANUP.md`, `terraform/setup.tf`, `nodepool-templates/*.yaml.tpl`
