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
    dotnet.yml  container.yml  claude-review.yml          # public entry points
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
| `container.yml` | Build → smoke test → save + digest → push only if still branch tip; tags `sha`/`latest`/semver; optional multi-arch, cosign, attestation; optional webhook redeploy + health check | `context`, `dockerfile`, `target`, `image`, `registry`, `platforms`, `smoke-command`, `sign`, `deploy-webhook-secret`, `health-url` | com, SkyNetHR, Adventures, Licensing, Blog, PSGenerator, GameEngine, Plugins.GitHub |
| `node-ci.yml` | OS × Node matrix; install; configurable script list (`typecheck`, `lint`, `test`, …); optional clean-tree check; aggregated required check | `node-versions`, `os`, `package-manager`, `scripts`, `setup-script`, `check-clean`, `submodules` | AgentKit, Git, GameOfLife, Adventures.Content, LandingPage, Data.Json |
| `pwsh-ci.yml` | Parse-check all `*.ps1`, Pester, optional coverage gate, test report | `pester-version`, `paths`, `minimum-coverage`, `os` | Data.Json, GameEngine, SkyNetHR, GameOfLife, Workspace, PSGenerator |
| `dotnet.yml` | Setup SDK, feed auth, build, test (trx), coverage gate, pack, publish (GitHub Packages / nuget.org OIDC / API key), consume check | `solution`, `dotnet-version`, `os`, `pack`, `feed`, `minimum-coverage`, `version-strategy` | Platform, Licensing, Platform.Updater, Cleaner, HotCorners (CI only), WinGet (CI only) |
| `npm-package.yml` | Tag ↔ `package.json` check, pack, publish with provenance to npmjs or GitHub Packages, GitHub Release | `registry`, `access`, `provenance`, `github-release` | Data.Json, Plugins.GitHub, GameEngine, **ServiceContract** (new) |
| `pages.yml` | Static site / SPA build → Pages | `build-command`, `output`, `base-path` | Adventures.Content, Adventures, com, LandingPage |
| `claude-review.yml` | Claude Code PR review / `@claude` | `mode`, `model`, `skip-drafts`, `skip-bots`, `prompt` | 8 repos, 4 variants today |

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
| 4 | Containers | `container.yml`, `image-gate`, `branch-tip-gate`, `webhook-deploy` | com, SkyNetHR, Adventures, Licensing, Blog migrated |
| 5 | .NET | `dotnet.yml`, `nuget-feed`; GitVersion strategy in `version` | Platform, Licensing, Platform.Updater, Cleaner migrated; HotCorners/WinGet use it for CI |
| 6 | Consolidate | `claude-review.yml`, `pages.yml`; drift report (repo → pinned ref); `v1.0.0` | All SubZeroDev repos on `@v1`; `v1.0.0` tagged |
| 7 | Optional extensions | Environment promotion list with approvals; cloud deploys via OIDC (Azure Web App / Functions, etc.); secret-to-config token replacement | On demand |

Not templated: HotCorners Velopack release and WinGet Nuke release stay repo-local.

## Open questions

1. Default runner OS — `ubuntu-latest` everywhere with `os` input, or `windows-latest` default for `dotnet.yml` (Cleaner/HotCorners/WinGet need Windows)?
2. ~~Docs builder: PowerShell or a Node CLI?~~ Resolved: PowerShell, which the build-agent image already has.
3. Starter workflows: add a `workflow-templates/` set to a `The-Running-Dev/.github` repository for the "New workflow" UI?
4. Claude review: include it in the public library, or keep it as a SubZeroDev-only shared workflow?
