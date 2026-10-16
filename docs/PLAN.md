# GitHub-ActionTemplates — Rebuild Plan

Goal: do for GitHub what `Demo-AzureDevOps-Templates` did for Azure DevOps — one short
pipeline file per repository, backed by versioned, tested, shared templates — as a
**generic public library**. The `The-Running-Dev/SubZeroDev.*` repositories are the first
consumers and the proving ground, not the design target.

## Decisions

| Topic | Decision |
|---|---|
| Scope | Generic public library; SubZeroDev conventions are inputs, never defaults |
| Location | Rebuild this repository in place (keep name + history, remove current scaffolding) |
| Consumer pinning | Moving major tag `@v1`; immutable `v1.x.y` tags also published |
| Extraction | Every step a consumer needs is a reusable action or workflow here; a repository adds only what is specific to it, as scripts in its own repository passed by path |
| Workflow YAML | No script code in `run:` or in inputs; `run:` only calls a script file |
| Docs builder | Build-agent image v2 (`ghcr.io/the-running-dev/build-agent`, pinned by digest) runs `build node-template` with a Docusaurus template bundled in `actions/docs-build/template`; no separate docs image |

## What carries over from Azure DevOps

| Azure DevOps | GitHub |
|---|---|
| `resources.repositories` + `template: X/stages.yml@Templates` | `uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/<archetype>.yml@v1` |
| `<Archetype>/stages.yml` (entry point) | Public reusable workflow per archetype |
| `01.artifacts.yml`, `02.release.yml`, `03.jobs.yml` | Internal reusable workflows `_build-*.yml`, `_publish-*.yml` |
| `Common/*.yml` step templates | Composite actions `actions/<name>/action.yml` |
| `Common/Scripts/*.ps1`, `Functions.psm1` | Scripts beside each action, run via `${{ github.action_path }}`; shared module in `actions/_lib/` |
| `00.variables.yml` naming conventions | `context` action: derives names/versions, emits outputs (no org-specific defaults) |
| Pipeline `name:` + `isPreviewVersion` | `version` action: strategies `tag`, `manifest`, `gitversion`, `run-number`; prerelease on non-tag pushes |
| `Build.Reason == PullRequest` → validate only | Publish/deploy jobs gated on `github.event_name != 'pull_request'` |
| `validate-code-coverage.yml` (55 % default) | `coverage-gate` action (Cobertura + JaCoCo), writes job summary; default off, opt-in threshold |
| `debug.yml` | `debug` action: dumps inputs, github context, runner info |
| `environment:` + approvals | GitHub Environments via `environment` input |
| Service connections | OIDC (NuGet trusted publishing, npm provenance, cloud logins); secrets fallback |
| `azure-pipelines.example.yml` + per-archetype README | `examples/<archetype>.yml` + `docs/<archetype>.md` |

Not ported: CRQ/JIRA, Azure resource tagging, AKS/Keda, SonarQube-specific steps, the
hand-written 5-environment `dependsOn`/`condition` chain (replaced by an optional
environment list in Phase 7).

## GitHub constraints the design must respect

1. Reusable workflows must live flat in `.github/workflows/` — no subfolders.
2. Inside a reusable workflow, `uses: ./actions/x` resolves to the **caller's** checkout. Templates
   reference their own actions with the self-repository syntax `uses: $/actions/x` (GitHub,
   2026-07-30; runner ≥ 2.336.0), which resolves to this repository at the exact commit the
   caller pinned — `@v1`, `@v1.2.3` or a SHA. actionlint 1.7.12 does not parse `$/` yet
   (rhysd/actionlint#711), so `.github/actionlint.yaml` ignores those errors only.
3. A called workflow cannot exceed the caller's `GITHUB_TOKEN` permissions — every example
   declares `contents`, `packages`, `pages`, `id-token`, `attestations` as needed.
4. `workflow_call` inputs have no object type — maps are JSON strings read with `fromJSON`.
5. `GITHUB_TOKEN` is reserved and cannot be declared as a `workflow_call` secret.
6. Marketplace lists only root-level `action.yml`; sub-directory actions are usable but unlisted.
7. `secrets: inherit` only works within the same owner — external consumers pass secrets explicitly,
   so every secret is declared with a documented name.

## Current repository state (to be removed)

- Workflows live in `templates/` and `.github/templates/` — not callable.
- "Composite actions" are bare `.yml` files and referenced via `./` — not valid.
- `nodejs-release.yml` declares a `GITHUB_TOKEN` secret — fails validation.
- Two diverged copies; `upload-artifact@v3` (retired) and `actions/create-release@v1` (archived).

## Target layout

```
.github/
  workflows/
    docs.yml  pages.yml  node-ci.yml  npm-package.yml  pwsh-ci.yml
    dotnet.yml  container.yml                             # public entry points
    _build-*.yml  _publish-*.yml                          # internal
    self-test.yml   # runs every entry point against tests/fixtures
    lint.yml        # actionlint + zizmor
    release.yml     # semver tag, CHANGELOG, move v1
  dependabot.yml    # github-actions + docker, weekly, grouped
actions/
  _lib/Functions.psm1
  version/  context/  debug/  assert-tag-version/  docs-build/  coverage-gate/  test-report/
  pwsh-check/  nuget-feed/  webhook-deploy/  branch-tip-gate/  image-gate/
tests/fixtures/
  dotnet-lib/  npm-lib/  node-app/  pwsh-module/  docusaurus/  dockerfile/
examples/<archetype>.yml
docs/<archetype>.md  docs/conventions.md  docs/migration.md
```

## Archetypes (public entry points)

Ordered by demand observed across the SubZeroDev repositories.

| Workflow | Does | Key inputs | First consumers |
|---|---|---|---|
| `docs.yml` | Build docs (bundled template or the folder's own Node project) in the build-agent container → Pages on default branch and tags | `source`, `builder` (`template`/`node`), `template`, `image`, `title`, `pre-build`, `post-build` (covers the old `test-script`) | PluginContract, Specs, SunTrap, Plugins.GitHub, Blog, WinGet, Platform, GameEngine, PSGenerator, Workspace |
| `container.yml` | Build → smoke test → save + digest → push only if still branch tip; tags `sha`/`latest`/semver; optional multi-arch, cosign, attestation; optional webhook redeploy + health check | `context`, `dockerfile`, `target`, `image-name`, `registry`, `tags`, `platforms`, `smoke-*`, `sign`, `deploy`, `health-url` | com, SkyNetHR, Adventures, Licensing, Blog, PSGenerator, GameEngine, Plugins.GitHub |
| `node-ci.yml` | OS × Node matrix; install; configurable script list (`typecheck`, `lint`, `test`, …); optional clean-tree check; aggregated required check | `node-versions`, `os`, `package-manager`, `scripts`, `setup-script`, `check-clean`, `submodules` | AgentKit, Git, GameOfLife, Adventures.Content, LandingPage, Data.Json |
| `pwsh-ci.yml` | Parse-check all `*.ps1`, Pester, optional coverage gate, test report | `pester-version`, `paths`, `minimum-coverage`, `os` | Data.Json, GameEngine, SkyNetHR, GameOfLife, Workspace, PSGenerator |
| `dotnet.yml` | Setup SDK, feed auth, build, test (trx), coverage gate, pack, publish (GitHub Packages / nuget.org OIDC / API key), consume check | `solution`, `dotnet-version`, `os`, `pack`, `feed`, `minimum-coverage`, `version-strategy` | Platform, Licensing, Platform.Updater, Cleaner, HotCorners (CI only), WinGet (CI only) |
| `npm-package.yml` | Tag ↔ `package.json` check, pack, publish with provenance to npmjs or GitHub Packages, GitHub Release | `registry`, `access`, `provenance`, `github-release` | Data.Json, Plugins.GitHub, GameEngine, **ServiceContract** (new) |
| `pages.yml` | Static site / SPA build with Node → Pages on default branch and tags | `scripts`, `output`, `base-path`, `spa`, `env` + `BUILD_ENV`, `artifact`, `post-deploy` | Adventures.Content, Adventures, com, LandingPage |

Event semantics are identical across archetypes:
- `pull_request` → build + test only.
- push to default branch → build + test + prerelease publish / deploy.
- tag `v*` → stable release (tag must equal manifest version).

## Docs builder

- The build job runs in the build-agent image v2, which has Node, pnpm, PowerShell, git and
  `build node-template` (clone a template, overlay the docs folder, install, `build:prod`).
- The generic Docusaurus template from `SubZeroDev.Workspace/docs-template` lives in
  `actions/docs-build/template` (title, URL and base URL from the environment and Pages
  settings; no SubZeroDev defaults). The action turns it into a local git repository for
  `build node-template`; `template:` points at another template repository instead.
- Workspace artifacts are never copied: `cookies.txt`, `storage/`, `api/`, `artifacts/`,
  `.docusaurus/`, `.build/`.
- The image digest in `docs.yml` is bumped by hand; Dependabot covers the template's npm packages.
- `merge-site` (merging another site into the output) is deferred until a consumer needs it.
- `docs-template:latest` stays available to unmigrated repositories, then is deprecated.

## Quality bar (public library)

- Third-party actions pinned to commit SHA; Dependabot bumps them.
- zizmor + actionlint on every PR; no `pull_request_target`; inputs never interpolated directly into `run:` (passed via `env:`).
- Every entry point exercised by `self-test.yml` on ubuntu + windows against `tests/fixtures`.
- Inputs are a public contract: additive changes in minor versions, removals only in a major,
  deprecations warn for one minor release first.
- CHANGELOG + GitHub Release per tag; `docs/<archetype>.md` generated input tables checked in CI.

## Phases

| # | Phase | Work | Exit criteria |
|---|---|---|---|
| 1 | Foundation | Remove `templates/`, `.github/templates/`, example-workflows; new layout; `lint.yml`, `release.yml`, `dependabot.yml`; actions `debug`, `version`, `assert-tag-version`, `context` | `v0.1.0` released; lint + self-test green |
| 2 | Docs (pilot) | `docs-build` action + bundled template on the build-agent image, `docs.yml`, fixtures; `run-scripts`, `changelog`, `node-scripts` for per-repository steps; migrate PluginContract + Specs, then the remaining repositories | Docs repos on `docs.yml@v0`; callers pass only script paths and settings |
| 3 | Node + PowerShell | `node-ci.yml`, `pwsh-ci.yml`, `pwsh-check`, `coverage-gate`, `test-report`, `npm-package.yml`; give ServiceContract a pipeline | Node/pwsh repos migrated |
| 4 | Containers | `container.yml`, `image-meta`, `image-gate`, `image-archive`, `branch-tip-gate`, `image-push`, `webhook-deploy` | com, SkyNetHR, Adventures, Licensing, Blog migrated |
| 5 | .NET | `dotnet.yml`, `nuget-feed`; GitVersion strategy in `version` | Platform, Licensing, Platform.Updater, Cleaner migrated; HotCorners/WinGet use it for CI |
| 6 | Consolidate | `pages.yml`; drift report (repo → pinned ref); `v1.0.0` | All SubZeroDev repos on `@v1`; `v1.0.0` tagged |
| 7 | Optional extensions | Environment promotion list with approvals; cloud deploys via OIDC (Azure Web App / Functions, etc.); secret-to-config token replacement | On demand |

Not templated, so these stay repo-local:

- HotCorners Velopack release and WinGet Nuke release.
- SubZeroDev.Platform.UI.Portfolio `deploy-pages.yml`: it is Portfolio's own published reusable workflow,
  with the root `action.yml`, that other repositories call. It is not a consumer of `pages.yml`.
- subzerodev-s21-proof `ci.yml`: a throwaway S21 proof fixture whose `check` job only exits 0,
  to satisfy its ruleset's required check.

The drift report lists these repositories as `unused`, and that is expected.

### Phase 3 decisions

- `node-ci.yml` and `pwsh-ci.yml` run on hosted runners with `setup-node` and the runner's
  PowerShell 7, so a matrix can include Windows and macOS. `npm-package.yml` builds on
  `ubuntu-latest`.
- Every matrix workflow ends with a `Result` job (`needs-gate`): branch protection requires
  `<caller job> / Result`, which does not change when the matrix does.
- `npm-package.yml` publishes tag builds only by default; `publish-prereleases: true` adds
  `1.2.3-ci.N` builds from the default branch under the `next` dist-tag.
- npm trusted publishing is registered with the **calling** workflow's file name.
- Migration targets, each in its own pull request: Data.Json (`npm-package.yml` + `pwsh-ci.yml`),
  GameOfLife, Adventures.Content, GameEngine, SkyNetHR and PSGenerator (`node-ci.yml` and/or
  `pwsh-ci.yml`), and a new pipeline for ServiceContract (`node-ci.yml` + `npm-package.yml`).

### Phase 4 decisions

- `container.yml` has four jobs:
  - `Build` builds with Buildx and loads the image, smoke-tests it with `image-gate`, and saves
    it with its image ID as an artifact (`image-archive`).
  - `Publish` (default branch and tags, `push: true`) runs `branch-tip-gate` first, then loads
    that archive and checks the image ID, tags it (`image-meta`) and pushes with `image-push`, and
    optionally signs (cosign, keyless) and attests build provenance. What was tested is what is
    pushed; it is never rebuilt.
  - `Deploy` (`deploy: true`) calls the redeploy webhook, waits for the health URL with
    `webhook-deploy`, then runs `post-deploy` scripts.
  - `Result` (`needs-gate`) is the one check to require.
- Multi-platform (`platforms`): `Build` smoke-tests the runner's platform. `Publish` rebuilds
  every platform from the GitHub Actions cache and pushes, because `docker load` cannot hold a
  multi-platform image.
- Tags are kinds in `tags`: `sha`, `short-sha`, `version`, `minor`, `major`, `date`, `branch`,
  `latest`. The default is `sha latest`. `minor`, `major` and `latest` apply to stable builds
  only: `latest` on default-branch pushes and stable tags. Labels are the OCI set (source,
  revision, created, version, title).
- `require-tip` handles a run that is no longer the branch tip when it reaches `Publish`:
  - `all` (default): push nothing and end green with a summary note.
  - `latest`: push the commit's tags but not `latest`.
  - `none`: push everything regardless.
  The gate, not a concurrency group, orders pushes: a run that lost the race pushes nothing (or
  no `latest`), and no push is ever cancelled half-way.
- The smoke test runs the container with `smoke-env` and `smoke-options`, waits for Docker's
  HEALTHCHECK if the image has one, then probes `smoke-port` + `smoke-path` for `smoke-status`
  (`any` accepts any answer), then copies the `smoke-exec` scripts into the container and runs
  them there. After that, `smoke-npm-scripts` (package.json) and `smoke-scripts` (repository
  scripts) run on the runner with `IMAGE`, `CONTAINER` and `SMOKE_URL` set.
- Secrets are declared by name:
  - `REGISTRY_TOKEN`: falls back to `github.token`.
  - `BUILD_SECRETS`: BuildKit `id=value` lines.
  - `DEPLOY_WEBHOOK_URL`.
  - `DEPLOY_TOKEN`: given to `post-deploy` scripts.
  The caller grants `contents: read`, `packages: write`, `id-token: write` and
  `attestations: write`.
- Left to the caller: path filters, change detection, approval gates beyond the `environment`
  input, and building a tree in an earlier job. The `artifact` input downloads that tree into the
  build context.
- Migration targets, each in its own pull request: com, SkyNetHR, Adventures (two images, one
  deploy), Licensing and Blog. PSGenerator, GameEngine and Plugins.GitHub follow when convenient.
  PSGenerator's required `Build and publish image` check becomes `<job> / Result`.

### Phase 5 decisions

- `dotnet.yml` runs on hosted runners with `os` defaulting to `["ubuntu-latest"]`, like the other
  matrix workflows. Windows-only solutions pass `os: '["windows-latest"]'`; Linux runners can
  still build `net*-windows` projects with `enable-windows-targeting`.
- Jobs:
  - `Test` (per runner) restores, builds and tests with `dotnet-test`: TRX results to
    `test-report`, coverlet reports merged into one so a line is counted once across test
    projects, then `coverage-gate`.
  - `Pack` (`pack: true`, one runner) computes the version, packs with `dotnet-pack` and uploads
    the packages. What is published is what was packed.
  - `Publish` pushes with `nuget-push` from tags, and from the default branch with
    `publish-prereleases`. One publish at a time per repository.
  - `Post-publish` runs repository scripts with `PACKAGE_VERSION`, for checks such as restoring
    the package that was just published.
  - `GitHub release` (`github-release: true`) attaches the packages to the release.
  - `Result` (`needs-gate`) is the one check to require.
- Versions: `manifest` (the default) reads `<Version>` from Directory.Build.props or the
  project; `version` gained a `gitversion` strategy, which uses the repository's tool manifest
  when it lists GitVersion.Tool, else installs the pinned `gitversion-version`. The version is
  passed as `-p:Version` and `dotnet-pack` fails when a package does not carry it.
- Private feeds: `nuget-feed` writes the sources and credentials to the user-level NuGet config
  with the password `%NUGET_FEED_TOKEN%`, so the token stays in the environment of the steps that
  restore. It falls back to `github.token`. A repository nuget.config with `<clear />` keeps its
  sources; those are listed by name only and get credentials.
- Publishing: GitHub Packages with `github.token` (default), nuget.org trusted publishing through
  NuGet/login (`nuget-user`, `id-token: write`), or an API key secret. `skip-duplicate` makes a
  re-run pass. Symbol packages go to nuget.org only.
- Left to the caller: HotCorners' Velopack release and WinGet's Nuke release; those repositories
  use `dotnet.yml` for CI only.
- Migration targets, each in its own pull request: Cleaner, HotCorners (CI), Platform.Updater,
  Licensing, Platform, then WinGet (CI).

### Phase 6 decisions

- `pages.yml` builds on a hosted runner with `actions/setup-node` and `node-scripts`, not the
  build-agent container: the sites are plain Node projects, and `docs.yml` stays the Docusaurus
  path.
- `pages-env` reads the address from the Pages settings (custom domains included) and exports
  `PAGES_URL`, `PAGES_ORIGIN` and `PAGES_BASE_PATH`; before Pages is set up it falls back to
  the github.io address, so pull requests and forks build without `configure-pages` failing.
- Build variables: `env` (`KEY=value` lines, for `vars`) and the `BUILD_ENV` secret (masked),
  instead of one input per variable.
- `spa: true` copies `index.html` to `404.html` for client-side routes.
- The deploy job runs `branch-tip-gate` inside the `pages-deploy` concurrency group, so an older
  run that waited never replaces a newer site; `artifact` deploys a tree built and tested by an
  earlier job (com), and `post-deploy` checks the live site.
- Migration targets, each in its own pull request: Adventures.Content, Adventures,
  LandingPage, com.
- The drift report is the `drift-report` action plus a weekly `drift.yml` in this repository, not
  a reusable workflow: it reads every repository of the owner through the API (`DRIFT_TOKEN`
  for private ones) and never checks one out. It reads workflow files on default branches only
  and reports a ref as current when it resolves to the latest `vX.Y.Z` release's commit, so
  `@v0` is current until `v1.0.0` ships. Its `unused` list tracks the repositories still to
  migrate.

## Open questions

1. ~~Default runner OS for `dotnet.yml`?~~ Resolved: `["ubuntu-latest"]`, as for every matrix
   workflow; Windows repositories pass their own `os`.
2. ~~Docs builder: PowerShell or a Node CLI?~~ Resolved: PowerShell, which the build-agent image already has.
3. Starter workflows: add a `workflow-templates/` set to a `The-Running-Dev/.github` repository for the "New workflow" UI?
4. ~~Claude review: include it in the public library, or keep it as a SubZeroDev-only shared workflow?~~
   Resolved: SubZeroDev-only. It lives at `The-Running-Dev/.github/.github/workflows/claude-review.yml`,
   outside this library.
