# Docs Sync Checklist

Rules for keeping documentation in sync with code changes in this repo.

---

## When to update README.md

Update the root README when:

- A new input variable is added to `variables.tf` — add to the Configuration table
- A new example directory is created — add to the Examples table with one-line description
- Provider version constraints change in `versions.tf` — update Prerequisites badges
- A new prerequisite tool is required — add to Prerequisites list
- The quick-start flow changes (new steps, different ordering)
- A new output is added to `outputs.tf` that users need to know about
- The `base_domain` / DNS behavior changes — update the domain section

Do NOT update README for:
- Internal refactoring that doesn't change user-facing behavior
- Changes to `claude-md/` docs (these are gitignored, not user-facing)
- CI/CD pipeline changes (document in CONTRIBUTING.md instead)

---

## When to update claude-md/TAGGING.md

Update when:

- Adding or removing a tagging layer
- Changing the IAM policy approach for custom tags
- Discovering a new resource type that `default_tags` cannot reach
- Fixing a tag-not-landing issue (add to debugging section)
- Changing tag key names or default values in `variables.tf`
- Modifying `terraform/tagging.tf`, `terraform/ingressclass.tf`, or the
  `spec.tags` block in any `.tpl` file
- The EKS module version changes and affects tag propagation behavior

Keep in sync with: `terraform/tagging.tf`, `terraform/ingressclass.tf`,
`terraform/eks.tf` (cluster_tags), `terraform/main.tf` (default_tags),
`nodepool-templates/*.yaml.tpl` (spec.tags).

---

## When to update claude-md/CLEANUP.md

Update when:

- `scripts/cleanup.sh` gains new flags or changes existing flag behavior
- A new resource type is discovered that can orphan on cluster deletion
- The drain-before-destroy ordering changes
- A new verification command is needed post-cleanup
- A new Auto Mode gotcha affects cleanup (e.g., new managed resources)
- The post-destroy orphan checklist needs a new entry

Keep in sync with: `scripts/cleanup.sh` (flags, usage, ordering).

---

## When to update SECURITY_CONSIDERATIONS.md

Update when:

- IAM role scope changes (more permissive or more restrictive)
- Network exposure changes (new public endpoints, security group rules)
- Encryption settings change (KMS key usage, at-rest/in-transit)
- A new Pod Identity association is added
- The external-dns IAM scoping changes
- Default security posture changes (e.g., `enable_domain` default)

---

## Docusaurus site sync (misc/website/)

The GitHub Pages site at `misc/website/` mirrors content from example READMEs.

When adding a new example:
1. Create the example's `README.md` first.
2. Add a sidebar entry in the Docusaurus config.
3. Verify the page renders correctly with `npm run build` in `misc/website/`.

The site does not auto-sync — manual rebuild and deploy is required.

---

## Example README standards

Every example directory under `examples/` should have a `README.md` that follows:

**Structure:**
1. Title (H1) — what this example demonstrates
2. Overview — 2-3 sentences explaining the pattern and why you'd use it
3. Prerequisites — what must be deployed first (link to root README Quick Start)
4. Deploy — step-by-step `kubectl apply` commands
5. Verify — commands to confirm the example is working
6. Observe (if applicable) — point to `examples/observability/`, do not inline
7. Clean up — how to remove just this example's resources

**Rules:**
- Use relative paths to reference other files in the repo (e.g., `../../nodepools/`)
- Keep observe/monitoring commands in `examples/observability/README.md`, not inline
- No `terraform` commands outside the root quick-start or `examples/observability/`
- Prerequisites should reference the base cluster deployment, not repeat it
- Include the rendered YAML filename if the example has a `.tpl` (remind users to
  run terraform first)

---

## PR description template

Use this structure for PRs to this repo:

```markdown
## What

Brief description of the change (1-2 sentences).

## Why

Context on why this change is needed.

## What else was updated

- [ ] README.md (if user-facing change)
- [ ] claude-md/TAGGING.md (if tag-related)
- [ ] claude-md/CLEANUP.md (if cleanup-related)
- [ ] SECURITY_CONSIDERATIONS.md (if security-related)
- [ ] .gitignore (if new rendered output)
- [ ] Example READMEs (if example behavior changed)

## Testing

How this was validated (terraform plan output, kubectl apply, etc.)
```

---

## Cross-reference: which docs cover which code

| Code file | Primary doc | Secondary doc |
|-----------|-------------|---------------|
| `terraform/main.tf` | README (Prerequisites) | TAGGING.md (Layer 1) |
| `terraform/eks.tf` | README (Components) | TAGGING.md (Layer 2) |
| `terraform/variables.tf` | README (Configuration) | — |
| `terraform/setup.tf` | — (internal plumbing) | file-relationships.md |
| `terraform/tagging.tf` | TAGGING.md (Layer 4) | README (5-layer mention) |
| `terraform/ingressclass.tf` | TAGGING.md (Layer 5) | — |
| `terraform/alb-acm.tf` | README (Domain/DNS section) | SECURITY_CONSIDERATIONS.md |
| `terraform/observability.tf` | examples/observability/README.md | README (feature list) |
| `nodepool-templates/*.yaml.tpl` | TAGGING.md (Layer 3) | README (architecture) |
| `scripts/cleanup.sh` | CLEANUP.md | README (Cleanup section) |
| `examples/*/` | Each example's own README.md | Root README examples table |

---

## Staleness signals

Watch for these signs that docs are out of sync:

- README mentions a variable that no longer exists in `variables.tf`
- TAGGING.md references a file path that has moved
- CLEANUP.md flags don't match `scripts/cleanup.sh --help` output
- Example README references a YAML file that is now template-rendered
- Version badges in README don't match `versions.tf` constraints
- The examples table in README is missing a directory that exists in `examples/`

Run this quick check:
```bash
# Examples in filesystem vs README
diff <(ls examples/ | sort) <(grep -oP '(?<=examples/)\w+' README.md | sort -u)
```

---

## Sources

- [This repo (sample-aws-eks-auto-mode)](https://github.com/aws-samples/sample-aws-eks-auto-mode)
- [EKS Auto Mode user guide](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Skill format reference](https://github.com/anthropics/skills/tree/main/skills/skill-creator)
- Internal: `claude-md/TAGGING.md`, `claude-md/CLEANUP.md`, `README.md`, `SECURITY_CONSIDERATIONS.md`
