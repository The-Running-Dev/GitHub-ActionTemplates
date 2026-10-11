# docs.yml

Builds a Docusaurus documentation site and deploys it to GitHub Pages.

| Run | Builds | Deploys |
|---|---|---|
| Pull request | yes | no |
| Push to the default branch, tag | yes | yes |
| Push to another branch | yes | no |

The build runs in the [build-agent image](https://github.com/The-Running-Dev/Docker-BuildAgent)
(`ghcr.io/the-running-dev/build-agent`, pinned by digest), which already has Node, pnpm,
PowerShell and git. The site is built by the [`docs-build`](../actions/docs-build/README.md)
action, uploaded as a Pages artifact and deployed by `actions/deploy-pages`.

## Set up

1. In the repository settings, under **Pages → Build and deployment**, set the source to
   **GitHub Actions**.
2. Put the documentation in `docs/` (Markdown in `docs/docs/`, or a full Docusaurus site).
3. Add the workflow ([examples/docs.yml](../examples/docs.yml)):

```yaml
name: Docs

on:
  push:
    branches: [main]
  pull_request:

permissions: {}

jobs:
  docs:
    permissions: { contents: read, pages: write, id-token: write }
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/docs.yml@v0
```

The caller must grant all three permissions even on pull requests, where the deploy job is
skipped: GitHub checks a reusable workflow's permissions before it runs any job.

## Documentation folder layouts

| Folder contains | Use | Result |
|---|---|---|
| `docs/*.md` only | defaults | Bundled template: title from the repository name, sidebar from the folders. |
| `docs/*.md`, `docusaurus.config.ts`, `sidebars.ts`, `src/` | defaults | Your files replace the template's; the template supplies `package.json` and the lockfile. Import only packages the template has. |
| A complete Node project (`package.json`, lockfile) | `builder: node` | Your dependencies and your build script. |
| Anything else that writes a static site | `builder: node`, `build-command`, `output` | Any generator that runs from a package.json script. |

Files in your folder always win over the template's. The bundled template's packages are
listed in [`actions/docs-build/template/package.json`](../actions/docs-build/template/package.json).

## Inputs

| Name | Default | Description |
|---|---|---|
| `source` | `docs` | Documentation folder, relative to the repository root. |
| `builder` | `template` | `template` (bundled or custom Docusaurus template) or `node` (the folder's own project). |
| `template` | bundled | Template git URL, optionally `<url>#<branch>`. The repository must be readable without credentials. |
| `package-manager` | from the lockfile | `npm`, `pnpm` or `yarn`. |
| `build-command` | `build` | package.json script for the `node` builder. |
| `output` | `<source>/build` | Folder the site ends up in. The `template` builder moves its site here, for example `artifacts/docs` for scripts that expect it there. |
| `title` | repository name | Site title for the bundled template. |
| `changelog` | | Page to generate from the git history before the build, relative to the repository root ([`changelog`](../actions/changelog/README.md)). Fetches the full history. |
| `changelog-front-matter` | | Front matter for the changelog page, one `key: value` per line. |
| `pre-build` | | Repository scripts run from the repository root before the build, by path, one per line ([`run-scripts`](../actions/run-scripts/README.md)). |
| `node-project` | | Node project folder whose scripts run after the build, for example a site that checks or merges the built docs ([`node-scripts`](../actions/node-scripts/README.md)). |
| `node-scripts` | `build` | package.json scripts `node-project` runs, in order. |
| `node-dependencies` | | Local Node projects `node-project` depends on, one per line; each is installed and built first. |
| `browser` | `false` | `true` provides a system Chromium or Chrome to `node-project` for browser tests. |
| `post-build` | | Repository scripts run from the repository root after the build, by path, one per line. |
| `deploy` | `true` | `false` only builds and uploads the artifact. |
| `image` | build-agent, by digest | Container image for the build job. It needs PowerShell 7, git and Node, and `build` for the `template` builder. |
| `runs-on` | `ubuntu-latest` | Runner for the build job; it must run Linux containers. |
| `fetch-depth` | `1` | `0` for full history (last-updated dates from git). Always `0` when `changelog` is set. |
| `submodules` | `false` | As for `actions/checkout`. |
| `artifact-name` | `github-pages` | Pages artifact name; change it when a workflow builds more than one site. |

## Outputs

| Name | Description |
|---|---|
| `page-url` | Deployed site URL; empty when nothing was deployed. |

## Steps

The build job runs, in order, only the steps whose inputs are set:

1. `changelog`: writes the changelog page.
2. `pre-build`: repository scripts, for example a documentation check or page generation.
3. The documentation build.
4. `node-project`: install the dependencies and the project, then run `node-scripts`.
5. `post-build`: repository scripts, for example a check of the built site.
6. Upload of `output` as the Pages artifact.

## Repository scripts

`pre-build` and `post-build` take script paths, not commands: a step that needs logic of its
own lives in a script in the calling repository, and the workflow YAML stays free of script
code. `.ps1` scripts run in PowerShell and fail the build by throwing, by a non-zero `exit` or
by a failing native command; other files must be executable. Paths are checked before the
first script runs.

## Examples

A title and a link check:

```yaml
    with:
      title: Plugin Contract
      post-build: ./build/Test-Documentation.ps1
```

Two checks before the build, then a site project that checks and merges the built docs with
browser tests, after building the engine it depends on:

```yaml
    with:
      output: artifacts/docs
      changelog: docs/docs/CHANGELOG.md
      changelog-front-matter: 'slug: changelog'
      pre-build: |
        ./build/Test-Documentation.ps1
        ./build/Test-SliceStatusMarkers.ps1
      node-project: site
      node-scripts: check merge
      node-dependencies: src/engine
      browser: true
```

A site with its own `package.json` in `website/` that builds to `website/dist`:

```yaml
    with:
      source: website
      builder: node
      output: website/dist
```

## Notes

- The base URL comes from the repository's Pages settings when deploying, so a custom domain
  needs no configuration. A site with its own `docusaurus.config.ts` can read `DOCS_URL` and
  `DOCS_BASE_URL` to do the same.
- Pull request builds use the default `https://<owner>.github.io/<repository>/` URL.
- The deploy job runs in the `github-pages` environment, one deployment at a time.
