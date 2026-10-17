# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). A release cannot be tagged without a
section for its version.

## [Unreleased]

### Fixed
- `node-scripts` (and so `node-ci` and `npm-package`) and `docs-build` call the package manager by
  its literal name. On Windows, the `npm.ps1` of npm 10.9.3 and earlier (Node 22.18.0's npm)
  rebuilds its arguments from the calling statement's text, so `& $manager run test` reached npm as
  `manager run test` and failed with `Unknown command: "manager"`. `debug` prints the npm version
  through the executable for the same reason.

## [0.8.3] - 2026-10-17

### Fixed
- `gates` gives a step marked `# verification: true` the job's or the workflow's
  `defaults.run.working-directory` as its `cd` prefix when the step sets no `working-directory`
  of its own, so the gate runs in the folder the step runs in.

## [0.8.2] - 2026-10-17

### Fixed
- `pester` runs the tests with `$PSNativeCommandUseErrorActionPreference = $false` (PowerShell's
  default) instead of leaking its own `$true`, so a test that runs a native command expected to
  fail (such as a child `pwsh` that exits 1) and checks `$LASTEXITCODE` no longer gets a
  `NativeCommandExitException`. This affects `pwsh-ci.yml`.

## [0.8.1] - 2026-10-16

### Fixed
- `pages.yml`: `post-deploy` scripts now get Node (`node-version`), the `artifact` and the
  submodules, as the build does, so a read-back check written in Node can run and compare the
  live site with the tree that was built.

## [0.8.0] - 2026-10-16

### Added
- `pages.yml` reusable workflow: builds a static site or single-page app with Node on a hosted
  runner and deploys it to GitHub Pages from the default branch and tags, skipping a commit that
  is no longer the branch head. The build gets `PAGES_URL`, `PAGES_ORIGIN` and
  `PAGES_BASE_PATH` from the Pages settings (or `base-path`), build variables from `env` and the
  masked `BUILD_ENV` secret, and `spa: true` adds the 404.html fallback. It can deploy a tree
  built by an earlier job (`artifact`) and run `post-deploy` scripts with the site address. A
  `Result` job is the one check to require. See `docs/pages.md`.
- `pages-env` action: exports the Pages address and build variables to the job.
- `pages-check` action: checks the built site and adds the single-page-app fallback.
- `drift-report` action: scans the repositories of an owner (or a list), finds the
  `uses: <library>/...@<ref>` lines in their workflows and reports each ref as `current`,
  `behind` (with the number of releases since), `unreleased`, `branch` or `unknown`, in the job
  summary, as warnings and as a JSON report. It also lists the repositories with workflows that
  do not use the library.
- `drift.yml`: runs `drift-report` every Monday for `The-Running-Dev` and uploads the report.
  Reads private repositories when the `DRIFT_TOKEN` secret is set.

## [0.7.1] - 2026-10-15

### Fixed
- `docs/dotnet.md` and the `dotnet.yml` header said a caller that never packs needs only
  `contents: read` and `packages: read`. GitHub checks the publish and release jobs' permissions
  before it starts the run, so such a caller fails with `startup_failure`; every caller grants
  `contents: write`, `packages: write` and `id-token: write`.
- `run-scripts` runs `.ps1` scripts with `$PSNativeCommandUseErrorActionPreference = $false`
  (PowerShell's default) instead of leaking its own `$true`, so a script that checks
  `$LASTEXITCODE` after a native command expected to fail (such as `git merge-base
  --is-ancestor`) no longer gets a `NativeCommandExitException`. This affects
  `pre-build`/`post-build` and the other script inputs of the reusable workflows.
  `$ErrorActionPreference` stays `Stop`, so a failing cmdlet still stops the script. A script
  still fails the step by throwing, by a non-zero `exit` or by finishing with a non-zero
  `$LASTEXITCODE`; a script that relied on a failing native command mid-script to stop it sets
  `$PSNativeCommandUseErrorActionPreference = $true` itself.

## [0.7.0] - 2026-10-13

### Added
- `dotnet.yml` reusable workflow: builds and tests a .NET solution on each runner in `os`, with a
  test report and a coverage gate over the merged coverlet reports; with `pack` it packs the
  NuGet packages once and publishes them from tags (and optionally the default branch) to GitHub
  Packages, nuget.org (trusted publishing or API key) or another feed, then can create the
  GitHub release with the packages attached. See [`docs/dotnet.md`](docs/dotnet.md).
- Actions `nuget-feed` (private feed credentials with the token read from the environment),
  `dotnet-test` (restore, build, test with TRX results and merged coverage), `dotnet-pack`
  (pack with a computed version in a deterministic CI build) and `nuget-push` (push, skipping
  versions already on the feed).
- `version` has a `gitversion` strategy (GitVersion.Tool from the repository's tool manifest, or
  the pinned `gitversion-version`).
- `gates` derives the gates of jobs that call `dotnet.yml`: their `pre-build` scripts, the restore,
  build and test of the solution, and their `post-build` scripts.

## [0.6.0] - 2026-10-12

### Added
- `container.yml` reusable workflow: builds an image with Buildx, starts it and smoke-tests it
  (HEALTHCHECK, HTTP probe, scripts inside the container and against it), then pushes the image
  that was tested from the default branch and tags, with optional multi-platform rebuild, cosign
  signature and build provenance attestation. A deploy job calls a redeploy webhook and waits for
  a health URL; a `Result` job gives branch protection one check. See
  [`docs/container.md`](docs/container.md).
- Actions `image-meta` (tags and OCI labels), `image-gate` (container smoke test),
  `image-archive` (hand an image between jobs, checking its ID), `branch-tip-gate` (hold back a
  build that is no longer the branch head), `image-push` (push, digest, cosign) and
  `webhook-deploy` (webhook with retries, then a health check).

## [0.5.1] - 2026-10-11

### Fixed
- `browser: true` on `node-ci.yml` and `actions/node-scripts` works on Windows and macOS: it
  finds Chrome in its install folders (the runner images ship it outside `PATH`) instead of
  failing because apt-get is Linux only. The browser is also exposed as `CHROME_PATH`.
- A Node project at the repository root (`working-directory: .`, the default) works on
  `node-ci.yml`, `npm-package.yml` and `actions/node-scripts`; it failed with "must be inside
  the workspace". `actions/pester` test and coverage paths and `actions/run-scripts`
  `working-directory` accept `.` too.

## [0.5.0] - 2026-10-09

### Added
- `actions/gates` and [`docs/gates.md`](docs/gates.md): a repository commits
  `.github/gates.json`, the commands its CI runs, for local verification to read. The action
  derives the list from the calls to `node-ci.yml`, `pwsh-ci.yml` and `npm-package.yml` and from
  steps marked `# verification: true`, and fails when the committed file differs.
- `gates-file` input on `node-ci.yml`, `pwsh-ci.yml` and `npm-package.yml`: the gates check runs
  once per run when the file exists.

## [0.4.0] - 2026-10-09

### Added
- `node-ci.yml` reusable workflow: installs a Node project and runs its scripts on an OS × Node
  matrix, then reports test results, gates coverage, optionally checks for a clean tree and
  uploads artifacts. A `Result` job gives branch protection one stable check.
- `pwsh-ci.yml` reusable workflow: syntax check and optional PSScriptAnalyzer, Pester with
  coverage on each OS, test report, coverage gate and a `Result` job.
- `npm-package.yml` reusable workflow: builds, tests and packs once with the package.json
  version (tag must match), publishes the tarball from tags to npmjs (trusted publishing,
  token) or GitHub Packages with provenance, optionally publishes default-branch prereleases
  under `next`, and creates the GitHub release with the CHANGELOG notes and the tarball.
- Actions `pwsh-check`, `pester` (Pester 5 or 6), `test-report`, `coverage-gate`,
  `check-clean`, `needs-gate`, `npm-pack`, `npm-publish` and `github-release`.
- `node-scripts` input `setup`: package.json scripts run before the install. pnpm and yarn are
  enabled through corepack when the runner does not have them.
- Shared module: `Install-PowerShellModule`, `Find-WorkspaceFile`, `Read-XmlFile`,
  `Get-CoverageReport`, `Get-TestResult`, `Get-ChangelogSection`, `Get-TarballManifest`,
  `Write-ActionAnnotation` and `Format-MarkdownCell`.
- Self-test runs of the three workflows against the `node-app`, `pwsh-module` and `npm-lib`
  fixtures, with their artifacts checked by `scripts/Test-CiArtifacts.ps1`.
- `tests/Metadata.Tests.ps1`: every `action.yml` is checked for unquoted values YAML would
  misread, inputs it never uses, and `INPUT_*` variables mapped to the wrong input.

### Changed
- The release workflow's self-test job is granted `contents: write` and `packages: write`, which
  `npm-package.yml` asks for.

## [0.3.0] - 2026-10-08

### Added
- `actions/run-scripts`: runs repository scripts by path, in order. Checks every path first and
  fails on a throw, a non-zero exit or a failing native command.
- `actions/changelog`: writes a Markdown changelog page from the git history, with pull request
  links and optional front matter.
- `actions/node-scripts`: installs a Node project and runs its package.json scripts in order,
  after building its local dependencies; `browser: true` provides a system Chromium.
- `docs.yml` inputs `changelog`, `changelog-front-matter`, `node-project`, `node-scripts`,
  `node-dependencies` and `browser`.
- `Split-ActionList`, `Get-PackageManager` and `Install-NodePackage` in the shared module.

### Changed
- `docs.yml`: **`pre-build` and `post-build` take script paths, one per line, instead of
  PowerShell code.** A caller that passed code moves it into a script in its repository.
- `docs-build`: the `template` builder moves the site to `output` when it is set, so a
  repository whose scripts expect `artifacts/docs` keeps them unchanged.
- This repository's workflows call scripts in `scripts/` instead of running inline code.

## [0.2.0] - 2026-10-08

### Added
- `docs.yml` reusable workflow: builds a Docusaurus site in the build-agent image
  (`ghcr.io/the-running-dev/build-agent`, pinned by digest) and deploys it to GitHub Pages from
  the default branch and tags. Inputs for the source folder, builder, template, pre/post-build
  PowerShell, title, runner and image.
- `actions/docs-build`: `template` builder (`build node-template` with a bundled, generic
  Docusaurus 3 template: Mermaid, local search, environment-driven URL and title) and `node`
  builder (the folder's own package.json).
- `Resolve-WorkspacePath` in the shared module: rejects paths outside the workspace.
- Self-test builds of the `tests/fixtures/docusaurus` and `tests/fixtures/docs-node` fixtures.
- Dependabot for the bundled template's npm dependencies.
- `docs/docs.md` and `examples/docs.yml`.

### Changed
- The release workflow grants `pages: write` and `id-token: write` to the self-test call, which
  now includes the docs workflow.

## [0.1.0] - 2026-10-08

Foundation release. The previous Copilot-generated templates are removed; they were not callable
(workflows outside `.github/workflows/`, composite actions without `action.yml`).

### Added
- `actions/version`: semantic version from the nearest tag, a manifest (package.json, MSBuild,
  PowerShell module, Cargo/pyproject, VERSION) or `base-version` + run number.
- `actions/assert-tag-version`: fails tag builds whose tag does not match the manifest version.
- `actions/context`: normalised event, branch, publish decision and image name outputs.
- `actions/debug`: run context, runner, tool versions, disk and workspace, without sensitive variables.
- Shared PowerShell module `actions/_lib/Functions.psm1` with Pester tests.
- `lint` (actionlint, zizmor, PSScriptAnalyzer), `self-test` (ubuntu, windows, macOS) and
  `release` (CHANGELOG notes, GitHub Release, moving major tag) workflows.
- Dependabot for GitHub Actions with a 7-day cooldown.
- `docs/conventions.md` and a README for every action.

### Changed
- In-repository references use the self-repository syntax (`uses: $/...`).
- README and CONTRIBUTING rewritten for the new layout.

### Removed
- `templates/`, `.github/templates/`, `.github/workflows/example-workflows/`, `docs/composition-examples.md`.
