import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import { themes as prismThemes } from 'prism-react-renderer';

// Default site configuration. A documentation folder with its own docusaurus.config.ts
// replaces this file; a folder with only markdown under docs/ is built with it.
//
// Without configuration the site is served from GitHub Pages at
// https://<owner>.github.io/<repository>/. DOCS_* environment variables override each value;
// the docs workflow sets DOCS_URL and DOCS_BASE_URL from the repository's Pages settings, so
// custom domains work too.
const [owner, repository] = (process.env.GITHUB_REPOSITORY || 'owner/docs').split('/');
const server = process.env.GITHUB_SERVER_URL || 'https://github.com';
const isUserSite = repository.toLowerCase() === `${owner.toLowerCase()}.github.io`;
const withSlashes = (path: string) => `/${path}/`.replace(/\/{2,}/g, '/');

const title = process.env.DOCS_TITLE || repository;
const url = process.env.DOCS_URL || `https://${owner.toLowerCase()}.github.io`;
// With DOCS_URL set an empty DOCS_BASE_URL means the site is served from the root.
const baseUrl = withSlashes(
  process.env.DOCS_URL || process.env.DOCS_BASE_URL
    ? process.env.DOCS_BASE_URL || '/'
    : isUserSite
      ? '/'
      : repository,
);
const repositoryUrl = process.env.DOCS_REPOSITORY_URL || `${server}/${owner}/${repository}`;

const config: Config = {
  title,
  tagline: process.env.DOCS_TAGLINE || '',
  url,
  baseUrl,
  onBrokenLinks: 'throw',
  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },
  i18n: { defaultLocale: 'en', locales: ['en'] },
  themes: [
    '@docusaurus/theme-mermaid',
    [
      '@easyops-cn/docusaurus-search-local',
      {
        hashed: true,
        docsRouteBasePath: '/',
        indexBlog: false,
      },
    ],
  ],
  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],
  themeConfig: {
    colorMode: { respectPrefersColorScheme: true },
    navbar: {
      title,
      items: [{ href: repositoryUrl, label: 'Repository', position: 'right' }],
    },
    footer: { style: 'dark' },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['powershell', 'csharp', 'bash', 'json', 'yaml'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
