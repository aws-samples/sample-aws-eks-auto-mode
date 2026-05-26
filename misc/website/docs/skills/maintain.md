---
sidebar_position: 2
title: "Skill: eks-automode-maintain"
description: "EKS Auto Mode repo maintenance skill for Claude Code. Covers the rendering chain, 5-layer tagging, docs sync, and PR checklist for maintainers."
keywords: [eks auto mode, maintenance, tagging, templatefile, docs sync, claude code skill, PR checklist]
---

# eks-automode-maintain

A Claude Code skill for maintainers of this repository who need to keep code, templates, and documentation in sync.

## When to use

Trigger this skill when you:

- Changed a `.tpl` file and need to know what else to update
- Want to verify 5-layer tagging consistency
- Are preparing a PR and need the checklist
- Need to update TAGGING.md or CLEANUP.md
- Want to understand the file dependency graph

## What it covers

### The rendering chain

```
nodepool-templates/*.yaml.tpl   (source of truth)
         |
         v  terraform apply (templatefile + local_file)
         |
nodepools/*.yaml                (rendered output)
```

Key gotcha: editing a `.tpl` does NOT reach the cluster until `terraform apply` re-renders. `kubectl apply` of stale rendered YAML silently reverts the fix.

### Decision matrix

| Changed | Also update |
|---------|-------------|
| `nodepool-templates/*.yaml.tpl` | `terraform apply` to re-render; verify `nodepools/` |
| `terraform/variables.tf` (new var) | `setup.tf` (pass to templatefile); README variable table |
| `terraform/eks.tf` | `claude-md/TAGGING.md` if tag-related; README if feature-facing |
| `examples/*` (new example) | README examples table; docs site sidebar; `setup.tf` if `.tpl` |
| `terraform/tagging.tf` | `claude-md/TAGGING.md`; verify 5-layer coverage |
| `scripts/cleanup.sh` | `claude-md/CLEANUP.md` flags/usage section |
| `terraform/versions.tf` | README prerequisites (provider versions) |
| `terraform/ingressclass.tf` | `claude-md/TAGGING.md` Layer 5 section |

### 5-layer tagging verification

| Layer | File | Tags |
|-------|------|------|
| 1. Provider `default_tags` | `terraform/main.tf` | All TF-direct resources |
| 2. `cluster_tags` | `terraform/eks.tf` | EKS primary security group |
| 3. NodeClass `spec.tags` | `nodepool-templates/*.yaml.tpl` | EC2, root EBS, ENIs |
| 4. StorageClass `tagSpecification` | `terraform/tagging.tf` | PVC-provisioned EBS |
| 5. IngressClassParams `spec.tags` | `terraform/ingressclass.tf` | ALBs, target groups |

### PR checklist

- [ ] Every `.tpl` change validated via `terraform apply`
- [ ] New variables in README Configuration section
- [ ] Tag changes reflected in `claude-md/TAGGING.md`
- [ ] Cleanup changes reflected in `claude-md/CLEANUP.md`
- [ ] New examples have README with prereqs and commands
- [ ] Rendered YAML paths in `.gitignore` if generated
- [ ] No hardcoded cluster names or account IDs
- [ ] Example READMEs use relative paths

### Reference docs (loaded on demand)

- `references/file-relationships.md` -- complete file map and dependency graph
- `references/tagging-consistency.md` -- full 5-layer verification with debug commands
- `references/docs-sync-checklist.md` -- when to update each doc file, PR template

## Sources

- [Tag propagation IAM policy](https://docs.aws.amazon.com/eks/latest/userguide/auto-cluster-iam-role.html#tag-prop)
- [Custom NodeClass creation](https://docs.aws.amazon.com/eks/latest/userguide/create-node-class.html)
- [EKS Auto Mode best practices](https://docs.aws.amazon.com/eks/latest/best-practices/automode.html)
- [This repository](https://github.com/aws-samples/sample-aws-eks-auto-mode)
- Internal: `claude-md/TAGGING.md`, `claude-md/CLEANUP.md`
