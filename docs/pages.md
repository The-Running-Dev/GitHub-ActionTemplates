# pages.yml

Builds a static site or single-page app with Node and deploys it to GitHub Pages.

| Run | Builds | Deploys |
|---|---|---|
| Pull request | yes | no |
| Push to the default branch, tag | yes | yes, when the commit is still the branch head |
| Push to another branch | yes | no |

The build runs on a hosted runner: [`node-scripts`](../actions/node-scripts/README.md) installs
the project and runs its package.json scripts, [`pages-check`](../actions/pages-check/README.md)
checks the output, and the folder is uploaded as a Pages artifact and deployed by
`actions/deploy-pages`. For a Docusaurus documentation folder use [`docs.yml`](docs.md).

## Set up

1. In the repository settings, under **Pages → Build and deployment**, set the source to
   **GitHub Actions**.
2. Add the workflow ([examples/pages.yml](../examples/pages.yml)):

```yaml
name: Pages

on:
  push:
    branches: [main]
  pull_request:

permissions: {}

jobs:
  pages:
    permissions: { contents: read, pages: write, id-token: write }
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/pages.yml@v1
```

The caller must grant all three permissions even on pull requests, where the deploy job is
skipped: GitHub checks a reusable workflow's permissions before it runs any job. Require the
`<job> / Result` check in branch protection.

## Base path

A project site is served under `/<repository>/`, so the bundler needs that base. The build gets:

| Variable | Example | Description |
|---|---|---|
| `PAGES_URL` | `https://octo-org.github.io/app/` | Site URL, with a trailing slash. |
| `PAGES_ORIGIN` | `https://octo-org.github.io` | Scheme and host. |
| `PAGES_BASE_PATH` | `/app/` | Path the site is served under, with leading and trailing slashes. |

They come from the repository's Pages settings, so a custom domain gives `/` with no
configuration. Before Pages is set up (and on forks) they fall back to the default
`https://<owner>.github.io/<repository>/`, or `/` for an `<owner>.github.io` repository.
`base-path` overrides the path.

Vite reads it in `vite.config.ts`:

```ts
export default defineConfig({ base: process.env.PAGES_BASE_PATH ?? '/' });
```

## Inputs

| Name | Default | Description |
|---|---|---|
| `working-directory` | `.` | Node project folder, relative to the repository root. |
| `node-version` | `lts/*` | Node version for `actions/setup-node`, in the build and for `post-deploy` scripts. |
| `package-manager` | from the lockfile | `npm`, `pnpm` or `yarn`. |
| `setup` | | package.json scripts run with `npm run` before the install, for example one that vendors local packages. |
| `scripts` | `build` | package.json scripts that build the site, in order. Empty skips Node, for a prebuilt `artifact`. |
| `dependencies` | | Local Node projects it depends on, one per line; each is installed and built first. |
| `browser` | `false` | `true` provides a system Chromium or Chrome, for prerendering or browser tests. |
| `env` | | Build variables as `KEY=value`, one per line, exported to every later build step. `GITHUB_*`, `RUNNER_*`, `ACTIONS_*`, `PATH`, `CI`, `NODE_OPTIONS` and the `PAGES_*` names are reserved. |
| `base-path` | from the Pages settings | Path the site is served under, exported as `PAGES_BASE_PATH`. |
| `output` | `dist` | Built site folder, relative to `working-directory`. |
| `spa` | `false` | Single-page app: copies `index.html` to `404.html` (unless the site has one) so deep links load the app. |
| `pre-build` | | Repository scripts run from the repository root before the install, by path, one per line ([`run-scripts`](../actions/run-scripts/README.md)). |
| `post-build` | | Repository scripts run from the repository root after the build, by path, one per line. |
| `artifact` | | Artifact from an earlier job of the calling workflow, downloaded before the build and again before `post-deploy`. |
| `artifact-path` | `.` | Folder the `artifact` is downloaded into. |
| `deploy` | `true` | `false` only builds and uploads the artifact. |
| `require-tip` | `true` | Skip the deployment when the commit is no longer the branch head ([`branch-tip-gate`](../actions/branch-tip-gate/README.md)). |
| `post-deploy` | | Repository scripts run after the deployment, by path, one per line, with the site address in `PAGES_URL`, Node and the downloaded `artifact`. |
| `cache` | | `actions/setup-node` dependency cache, `npm`. Empty turns caching off. |
| `cache-dependency-path` | | Lockfile(s) for the cache key, from the repository root. |
| `runs-on` | `ubuntu-latest` | Runner for the build job. |
| `fetch-depth` | `1` | `0` for full history. |
| `submodules` | `false` | As for `actions/checkout`. |
| `artifact-name` | `github-pages` | Pages artifact name; change it when a workflow builds more than one site. |
| `timeout-minutes` | `30` | Timeout of the build job. |
| `utility-runs-on` | `ubuntu-latest` | Runner for the Deploy and Result jobs. |

## Secrets

| Name | Description |
|---|---|
| `BUILD_ENV` | Secret build variables as `KEY=value`, one per line. Each value is masked in the log before it is exported. |

## Outputs

| Name | Description |
|---|---|
| `page-url` | Deployed site URL; empty when nothing was deployed. |

## Jobs

1. `Build`: checkout, the optional `artifact`, the Pages variables and `env`, then `pre-build`,
   the Node build, `post-build`, the site check and the upload.
2. `Deploy` (default branch and tags, `deploy: true`): checks the commit is still the branch
   head, deploys, then sets up Node and the `artifact` and runs `post-deploy`. One deployment at a
   time per repository.
3. `Result`: the one check to require.

## Examples

A Vite app with its API address and a secret key:

```yaml
    with:
      spa: true
      env: |
        VITE_API_URL=${{ vars.API_URL }}
        VITE_SUPABASE_URL=${{ vars.SUPABASE_URL }}
    secrets:
      BUILD_ENV: VITE_SUPABASE_ANON_KEY=${{ secrets.SUPABASE_ANON_KEY }}
```

A site in `site/` that vendors its packages first, then exports and checks its content:

```yaml
    with:
      working-directory: site
      setup: setup
      scripts: export:content validate:content build:site
      cache: npm
      cache-dependency-path: site/package-lock.json
```

A tree built and tested by an earlier job:

```yaml
jobs:
  build:
    # ...uploads the built site as the `site` artifact
  pages:
    needs: build
    permissions: { contents: read, pages: write, id-token: write }
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/pages.yml@v1
    with:
      artifact: site
      artifact-path: site
      scripts: ''
      output: site
      post-deploy: ./build/Test-LiveSite.ps1
```

## Notes

- `env` values are in the workflow file, so put secrets in `BUILD_ENV`, never in `env`.
- Every step after the Pages variables sees `env` and `BUILD_ENV`, including `pre-build` and
  `post-build` scripts.
- The deploy job uses the `pages-deploy` concurrency group rather than `pages`, which the GitHub
  starter workflow puts at the caller's workflow level and would make the job wait on itself.
