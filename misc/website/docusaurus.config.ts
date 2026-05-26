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
