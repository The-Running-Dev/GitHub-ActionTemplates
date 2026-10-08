# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). A release cannot be tagged without a
section for its version.

## [Unreleased]

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
