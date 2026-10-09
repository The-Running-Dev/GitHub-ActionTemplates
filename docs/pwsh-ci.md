# pwsh-ci.yml

Checks PowerShell files for syntax errors (and optionally PSScriptAnalyzer findings), runs the
Pester tests on each operating system, and reports the results and coverage.

| Job | Runs |
|---|---|
| `Test (<os>)` | One per runner: syntax check, analyzer, Pester, report, coverage, upload. |
| `Result` | Always. Fails when any test job failed or was cancelled. |

The jobs run on GitHub-hosted runners with their PowerShell 7. Pester and PSScriptAnalyzer are
installed at pinned versions from the PowerShell Gallery. Nothing is published.

## Set up

Add the workflow ([examples/pwsh-ci.yml](../examples/pwsh-ci.yml)):

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions: {}

jobs:
  ci:
    permissions:
      contents: read
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/pwsh-ci.yml@v0
    with:
      os: '["ubuntu-latest", "windows-latest"]'
      analyzer: true
      coverage: src
      minimum-coverage: '80'
```

In branch protection, require **`ci / Result`** (the caller's job name, then `Result`).

## What runs

1. Checkout, then the [gates check](gates.md) (first matrix job, when `.github/gates.json`
   exists).
2. `pre-build` repository scripts.
3. [`pwsh-check`](../actions/pwsh-check/README.md) on `paths`: every `.ps1`, `.psm1` and
   `.psd1` is parsed, and with `analyzer: true` PSScriptAnalyzer runs too. Each problem is
   annotated on its line.
4. [`pester`](../actions/pester/README.md) on `tests`: NUnit results in
   `test-results/pester.xml`, and with `coverage` a JaCoCo report in
   `coverage/pester-coverage.xml`. It fails on a failed test, a test file that cannot run, and
   when no tests ran (unless `allow-empty`).
5. [`test-report`](../actions/test-report/README.md) in the job summary, also after a failure.
6. [`coverage-gate`](../actions/coverage-gate/README.md) when `coverage` is set.
7. `post-build` repository scripts.
8. Upload of the results and coverage as `<artifact-name>-<os>`, also after a failure.

## Inputs

| Name | Default | Description |
|---|---|---|
| `os` | `'["ubuntu-latest"]'` | Runner labels as a JSON list. |
| `paths` | `.` | Folders or files to check, from the repository root, one per line. |
| `exclude` | | Wildcard patterns of paths the check skips, one per line. |
| `analyzer` | `false` | Also run PSScriptAnalyzer and fail on any finding. |
| `analyzer-settings` | | Settings file, from the repository root. Empty reports Error and Warning findings of the default rules. |
| `analyzer-version` | `1.25.0` | PSScriptAnalyzer version. |
| `tests` | `tests` | Pester test folders or files, from the repository root, one per line. |
| `pester-version` | `5.7.1` | Pester version (5.x or 6.x). |
| `tags` / `exclude-tags` | | Run only, or skip, tests with these tags, comma-separated. |
| `allow-empty` | `false` | Pass when no tests ran. |
| `coverage` | | Files or folders to measure coverage for, one per line. Empty turns coverage off. |
| `minimum-coverage` | `'0'` | Minimum line coverage percentage when `coverage` is set. |
| `pre-build` | | Repository scripts run before the checks, by path from the repository root, one per line. |
| `post-build` | | Repository scripts run after the tests. |
| `artifact-name` | `pester` | Artifact name prefix; the OS is appended. |
| `gates-file` | `.github/gates.json` | [Gates file](gates.md) checked against the workflows when it exists; empty turns the check off. |
| `fetch-depth` | `1` | Commits to fetch; 0 fetches all history. |
| `submodules` | `false` | `true`, `recursive` or `false`. |
| `timeout-minutes` | `30` | Timeout of each test job. |

The workflow has no outputs.

## Permissions

`contents: read`.
