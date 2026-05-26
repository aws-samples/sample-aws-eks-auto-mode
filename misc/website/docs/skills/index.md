---
sidebar_position: 5
title: Claude Code Skills
description: "Install EKS Auto Mode skills for Claude Code. Plugin marketplace setup, manual install, and local testing for onboarding and maintenance workflows."
keywords: [claude code, skills, plugin, eks auto mode, AI assistant, developer tools]
---

# Claude Code Skills

This repository ships as a [Claude Code](https://claude.ai/code) plugin with two skills for EKS Auto Mode.

| Skill | Audience | What it covers |
|-------|----------|----------------|
| [eks-automode-onboard](./onboard) | Newcomers | Concepts, deployment, example selection, troubleshooting |
| [eks-automode-maintain](./maintain) | Repo maintainers | Rendering chain, 5-layer tagging, docs sync, PR checklist |

## Install via plugin marketplace

The fastest path. Run these two commands inside Claude Code:

```bash
/plugin marketplace add https://github.com/aws-samples/sample-aws-eks-auto-mode.git
/plugin install eks-automode@sample-aws-eks-auto-mode
```

Both skills become available immediately as `/eks-automode:eks-automode-onboard` and `/eks-automode:eks-automode-maintain`.

## Alternative: manual install

Clone and copy the skill directories into your personal skills folder:

```bash
git clone https://github.com/aws-samples/sample-aws-eks-auto-mode.git
cp -r sample-aws-eks-auto-mode/skills/eks-automode-onboard ~/.claude/skills/
cp -r sample-aws-eks-auto-mode/skills/eks-automode-maintain ~/.claude/skills/
```

## Local testing (from repo root)

Load the plugin directly without installing:

```bash
claude --plugin-dir .
```

## What the skills do

### eks-automode-onboard

Helps you go from zero to a running EKS Auto Mode cluster. Covers:

- What Auto Mode manages vs what you manage
- Which example to deploy for your use case
- Step-by-step deployment walkthrough
- Common first-day issues and how to fix them

### eks-automode-maintain

Helps you keep this repo's code and docs in sync. Covers:

- The `templatefile()` rendering chain (why `.tpl` edits need `terraform apply`)
- 5-layer tagging consistency verification
- Decision matrix: "I changed X, what else needs updating?"
- PR checklist for maintainers

## Sources

- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Claude Code plugin system](https://github.com/anthropics/skills/tree/main/skills/skill-creator)
- [EKS Auto Mode documentation](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [This repository](https://github.com/aws-samples/sample-aws-eks-auto-mode)
