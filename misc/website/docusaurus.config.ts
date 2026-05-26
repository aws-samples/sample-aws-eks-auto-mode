import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

const config: Config = {
  title: 'EKS Auto Mode Samples',
  tagline: 'Learn EKS Auto Mode through deployable Terraform examples',
  favicon: 'img/favicon.svg',

  url: 'https://aws-samples.github.io',
  baseUrl: '/sample-aws-eks-auto-mode/',

  organizationName: 'aws-samples',
  projectName: 'sample-aws-eks-auto-mode',

  onBrokenLinks: 'warn',

  markdown: {
    format: 'detect',
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  headTags: [
    {
      tagName: 'meta',
      attributes: {name: 'keywords', content: 'EKS Auto Mode, eks automode, Amazon EKS Auto Mode, automate EKS, automate kubernetes, simplify kubernetes, managed kubernetes, kubernetes automation, EKS terraform, EKS examples, EKS tutorial, EKS cost optimization, EKS GPU, EKS Spot, EKS Graviton, Karpenter, NodePool, NodeClass'},
    },
    {
      tagName: 'meta',
      attributes: {property: 'og:type', content: 'website'},
    },
    {
      tagName: 'meta',
      attributes: {property: 'og:image', content: 'https://aws-samples.github.io/sample-aws-eks-auto-mode/img/og-card.png'},
    },
    {
      tagName: 'meta',
      attributes: {property: 'og:site_name', content: 'EKS Auto Mode Samples'},
    },
    {
      tagName: 'meta',
      attributes: {name: 'twitter:card', content: 'summary_large_image'},
    },
    {
      tagName: 'meta',
      attributes: {name: 'twitter:image', content: 'https://aws-samples.github.io/sample-aws-eks-auto-mode/img/og-card.png'},
    },
    {
      tagName: 'script',
      attributes: {type: 'application/ld+json'},
      innerHTML: JSON.stringify({
        '@context': 'https://schema.org',
        '@type': 'SoftwareSourceCode',
        name: 'EKS Auto Mode Samples',
        description: 'Learn Amazon EKS Auto Mode through deployable Terraform examples. Automate Kubernetes compute, storage, and networking with GPU, Spot, Graviton, and cost optimization patterns.',
        url: 'https://aws-samples.github.io/sample-aws-eks-auto-mode/',
        codeRepository: 'https://github.com/aws-samples/sample-aws-eks-auto-mode',
        programmingLanguage: ['HCL', 'YAML', 'Bash'],
        runtimePlatform: 'Amazon EKS',
        license: 'https://opensource.org/licenses/MIT-0',
        author: {
          '@type': 'Organization',
          name: 'AWS Solutions Architects',
        },
      }),
    },
  ],

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/aws-samples/sample-aws-eks-auto-mode/edit/main/misc/website/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    metadata: [
      {name: 'description', content: 'Learn Amazon EKS Auto Mode through deployable Terraform examples. Automate Kubernetes compute, storage, and networking. GPU, Spot, Graviton, cost optimization, and observability patterns.'},
      {name: 'og:description', content: 'Deployable Terraform examples for EKS Auto Mode. Automate Kubernetes the easy way. GPU, Spot, Graviton, ODCR, disruption budgets, and more.'},
    ],
    navbar: {
      title: 'EKS Auto Mode Samples',
      items: [
        {
          type: 'doc',
          docId: 'intro',
          position: 'left',
          label: 'Docs',
        },
        {
          to: '/docs/examples',
          position: 'left',
          label: 'Examples',
        },
        {
          to: '/docs/architecture',
          position: 'left',
          label: 'Architecture',
        },
        {
          href: 'https://github.com/aws-samples/sample-aws-eks-auto-mode',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {label: 'Introduction', to: '/docs/intro'},
            {label: 'Getting Started', to: '/docs/getting-started'},
            {label: 'Examples', to: '/docs/examples'},
            {label: 'Architecture', to: '/docs/architecture'},
          ],
        },
        {
          title: 'Resources',
          items: [
            {label: 'EKS Auto Mode docs', href: 'https://docs.aws.amazon.com/eks/latest/userguide/automode.html'},
            {label: 'Karpenter docs', href: 'https://karpenter.sh/docs/'},
            {label: 'AWS Samples', href: 'https://github.com/aws-samples'},
          ],
        },
        {
          title: 'More',
          items: [
            {label: 'GitHub', href: 'https://github.com/aws-samples/sample-aws-eks-auto-mode'},
            {label: 'Contributing', to: '/docs/contributing'},
          ],
        },
      ],
      copyright: `Built by AWS Solutions Architects · MIT-0 License · Copyright © ${new Date().getFullYear()} Amazon.com, Inc. or its affiliates.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'hcl', 'yaml', 'json'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
