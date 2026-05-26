# File Relationships and Dependency Graph

Complete map of `sample-aws-eks-auto-mode` with dependency flows for maintainers.

---

## Directory overview

```
sample-aws-eks-auto-mode/
├── terraform/              Core infrastructure (single apply creates everything)
├── nodepool-templates/     Template sources for NodePool/NodeClass YAML
├── nodepools/              Rendered output (gitignored) — never edit directly
├── examples/               11 self-contained example directories
├── scripts/                Operational scripts (cleanup, helpers)
├── claude-md/              Maintainer docs (TAGGING.md, CLEANUP.md) — gitignored
├── misc/website/           Docusaurus site for GitHub Pages
├── skills/                 Claude skills for this repo
├── README.md               User-facing entry point
├── SECURITY_CONSIDERATIONS.md  Security posture documentation
├── CONTRIBUTING.md         Contribution guidelines
└── .gitignore              Includes nodepools/, rendered example YAMLs, claude-md/
```

---

## terraform/ — file-by-file

| File | Purpose | Depends on | Depended on by |
|------|---------|------------|----------------|
| `main.tf` | AWS + helm + kubectl providers; `local.tags`, `local.azs`, `local.enable_domain`, `local.full_domain` | `variables.tf` | Everything (providers + locals) |
| `variables.tf` | All input variables (`name`, `region`, `tags`, `base_domain`, etc.) | — | `main.tf`, `eks.tf`, `setup.tf`, `vpc.tf`, `alb-acm.tf` |
| `versions.tf` | Provider version constraints (aws >=5.79, helm ~>2.17, kubectl ~>2.1) | — | `main.tf` (implicit) |
| `vpc.tf` | VPC module (3 AZ, public/private subnets, NAT, karpenter discovery tags) | `main.tf` locals | `eks.tf` (vpc_id, subnet_ids) |
| `eks.tf` | EKS cluster module; enables Auto Mode, custom tag IAM, cluster_tags | `vpc.tf`, `main.tf` | `setup.tf`, `tagging.tf`, `ingressclass.tf`, `observability.tf`, `alb-acm.tf`, `outputs.tf` |
| `setup.tf` | `templatefile()` rendering chain; `local_file` resources for all `.tpl` files | `eks.tf` (outputs), `main.tf` (locals), `.tpl` files | `nodepools/`, rendered example YAMLs |
| `tagging.tf` | Layer 4 StorageClass with `tagSpecification`; deletes legacy gp2 | `eks.tf`, `main.tf` (local.tags) | PVC-created EBS volumes |
| `ingressclass.tf` | Layer 5 IngressClassParams + IngressClass (internal or internet-facing) | `eks.tf`, `main.tf`, `alb-acm.tf` (if domain enabled) | ALB/TG tagging |
| `alb-acm.tf` | Route53 zone lookup, ACM wildcard cert, external-dns Helm + IAM | `eks.tf`, `main.tf` | `ingressclass.tf` (ACM validation dep) |
| `observability.tf` | CloudWatch Container Insights addon + IAM attachment | `eks.tf` | — |
| `outputs.tf` | Exports: configure_kubectl command, cluster_name, oidc_provider_arn, region | `eks.tf`, `variables.tf` | Users, CI |

---

## nodepool-templates/ — template sources

| File | Renders to | NodeClass name | Instance families |
|------|-----------|----------------|-------------------|
| `gpu-nodepool.yaml.tpl` | `nodepools/gpu-nodepool.yaml` | `gpu-nodeclass` | g5, g6, g6e, p5, p5e |
| `graviton-nodepool.yaml.tpl` | `nodepools/graviton-nodepool.yaml` | `graviton-nodeclass` | (ARM64 instances) |
| `neuron-nodepool.yaml.tpl` | `nodepools/neuron-nodepool.yaml` | `neuron-nodeclass` | inf2, trn1 |
| `spot-nodepool.yaml.tpl` | `nodepools/spot-nodepool.yaml` | `spot-nodeclass` | (Spot capacity) |

Each template receives these variables from `setup.tf`:
- `node_iam_role_name` — from `module.eks.node_iam_role_name`
- `cluster_name` — from `module.eks.cluster_name`
- `tags` — from `local.tags` (map)
- `kms_key_id` — from `var.ephemeral_storage_kms_key_id`

Every template includes `spec.tags: ${indent(4, yamlencode(tags))}` for Layer 3
tagging. If you add a new template, follow this pattern.

---

## The templatefile() rendering chain in detail

```
variables.tf          main.tf              setup.tf              .tpl file           Output
┌──────────┐     ┌──────────────┐     ┌──────────────────┐     ┌───────────┐     ┌───────────┐
│ var.tags │────►│ local.tags   │────►│ templatefile(    │────►│ ${tags}   │────►│ nodepools/│
│ var.name │     │  = merge(    │     │   "...tpl",      │     │ ${cluster}│     │ *.yaml    │
│          │     │    var.tags, │     │   { tags=...     │     │           │     │           │
│          │     │    Blueprint)│     │     cluster=...})│     │           │     │           │
└──────────┘     └──────────────┘     └──────────────────┘     └───────────┘     └───────────┘
                                              │
                                              ▼
                                      local_file resource
                                      (writes to disk)
```

**Adding a new template:**
1. Create `nodepool-templates/my-nodepool.yaml.tpl` with the standard variable placeholders.
2. Add a `resource "local_file" "setup_my_nodepool"` block in `setup.tf`.
3. Add the output path to `.gitignore`.
4. Run `terraform apply` to validate rendering.
5. Update README if user-facing.

---

## examples/ — how they relate to templates

| Directory | Has `.tpl`? | Rendered by `setup.tf`? | Purpose |
|-----------|-------------|-------------------------|---------|
| `batch-jobs/` | No | No | Job scheduling patterns |
| `capacity-reservation/` | Yes (`odcr-nodepool.yaml.tpl`) | Yes | ODCR targeting |
| `cost-optimization/` | No | No | Overprovision, consolidation |
| `disruption-budgets/` | No | No | NodePool disruption budget configs |
| `gpu/` | Yes (`lb-service.yaml.tpl`) | Yes | GPU inference with LB exposure |
| `graviton/` | Yes (`2048-ingress.yaml.tpl`) | Yes | ARM64 workload with Ingress |
| `neuron/` | Yes (`vllm-deployment.yaml.tpl`) | Yes | Inferentia2 vLLM |
| `observability/` | No | No | CloudWatch Container Insights |
| `pod-autoscaling/` | Yes (KEDA templates) | Yes (keda.tf) | HPA + KEDA scaling |
| `spot/` | Yes (`2048-ingress.yaml.tpl`) | Yes | Spot capacity with Ingress |
| `static-capacity/` | Yes (`static-nodepool.yaml.tpl`) | Yes | Fixed-size node pools |

Examples with `.tpl` files depend on `terraform apply` to produce usable YAML.
The rendered outputs are gitignored so users must run terraform before `kubectl apply`.

---

## scripts/

| File | Purpose |
|------|---------|
| `cleanup.sh` | Full cluster teardown: drain k8s resources, terraform destroy, orphan sweep |

The cleanup script implements the drain-before-destroy order documented in
`claude-md/CLEANUP.md`. Changes to the script should always be mirrored in the
CLEANUP.md flags/usage section.

---

## Docusaurus site (misc/website/)

Serves the GitHub Pages documentation. Content pages reference example READMEs.
When adding a new example, add a corresponding sidebar entry. The site is built
separately (`npm run build` in `misc/website/`); it does not affect terraform or
cluster operations.

---

## Dependency summary: what feeds what

```
variables.tf ──► main.tf (locals) ──┬──► eks.tf ──┬──► setup.tf ──► .tpl ──► nodepools/
                                    │             │
                                    ├──► vpc.tf   ├──► tagging.tf
                                    │             │
                                    └──► alb-acm.tf ──► ingressclass.tf
                                                  │
                                                  └──► observability.tf
```

**Critical path for tagging:**
```
var.tags ──► local.tags ──┬──► provider default_tags (Layer 1)
                          ├──► cluster_tags in eks.tf (Layer 2)
                          ├──► templatefile() in setup.tf ──► .tpl spec.tags (Layer 3)
                          ├──► tagSpecification in tagging.tf (Layer 4)
                          └──► ingressclass_tags_yaml in ingressclass.tf (Layer 5)
```

All 5 layers source from the same `local.tags`. A tag key/value change in
`variables.tf` propagates through all layers on `terraform apply` — but only
to newly-created resources. Existing EC2/EBS/ALBs keep their original tags.

---

## Sources

- [This repo (sample-aws-eks-auto-mode)](https://github.com/aws-samples/sample-aws-eks-auto-mode)
- [EKS Auto Mode user guide](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- Internal: `terraform/setup.tf`, `nodepool-templates/*.yaml.tpl`, `.gitignore`
