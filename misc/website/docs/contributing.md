---
sidebar_position: 10
title: Contributing
---

# Contributing

Contributions welcome! Please read our [Contributing Guidelines](https://github.com/aws-samples/sample-aws-eks-auto-mode/blob/main/CONTRIBUTING.md) and [Code of Conduct](https://github.com/aws-samples/sample-aws-eks-auto-mode/blob/main/CODE_OF_CONDUCT.md).

## Adding a new example

1. Create a directory under `examples/<name>/`
2. Add a `README.md` explaining the "why" and "how"
3. Include deployable manifests (`.yaml` or `.yaml.tpl` for templated)
4. Add a row to the examples table in the root `README.md`
5. Copy the README content into `misc/website/docs/examples/<name>.md` with Docusaurus frontmatter

## Local docs development

```bash
cd misc/website
npm install
npm start
```

The site opens at `http://localhost:3000/sample-aws-eks-auto-mode/`.
