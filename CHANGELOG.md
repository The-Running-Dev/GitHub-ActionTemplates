# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). A release cannot be tagged without a
section for its version.

## [Unreleased]

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
