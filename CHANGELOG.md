# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). A release cannot be tagged without a
section for its version.

## [Unreleased]

### Fixed
- `browser: true` on `node-ci.yml` and `actions/node-scripts` works on Windows and macOS: it
  finds Chrome in its install folders (the runner images ship it outside `PATH`) instead of
  failing because apt-get is Linux only. The browser is also exposed as `CHROME_PATH`.

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
