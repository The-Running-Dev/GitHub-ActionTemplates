# node-ci.yml

Installs a Node project and runs its package.json scripts on each Node version and operating
system, then reports the test results and coverage.

| Job | Runs |
|---|---|
| `Test (<os>, Node <version>)` | One per matrix entry: install, scripts, report, coverage, clean-tree check, upload. |
| `Result` | Always. Fails when any test job failed or was cancelled. |

The jobs run on GitHub-hosted runners with `actions/setup-node`, so the matrix can include
Windows and macOS. Every pull request, push and tag runs the same way; nothing is published.

## Set up

Add the workflow ([examples/node-ci.yml](../examples/node-ci.yml)):

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
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/node-ci.yml@v0
    with:
      node-versions: '["20", "22", "24"]'
      scripts: lint test
```

In branch protection, require **`ci / Result`** (the caller's job name, then `Result`). It
does not change when the matrix does, and it fails when any matrix job fails.

## What runs

1. Checkout, then `setup-node` with the matrix Node version.
2. `pre-build` repository scripts.
3. [`node-scripts`](../actions/node-scripts/README.md) in `working-directory`: builds the local
   `dependencies`, then runs the `setup` scripts, the install (`npm ci`,
   `pnpm install --frozen-lockfile` or `yarn install`, chosen by the lockfile; pnpm and yarn
   through corepack) and `scripts` in order. The first failing script stops the job.
4. `post-build` repository scripts.
5. [`test-report`](../actions/test-report/README.md) when `test-results` is set, also after a
   failure.
6. [`coverage-gate`](../actions/coverage-gate/README.md) when `coverage-reports` or
   `minimum-coverage` is set.
7. [`check-clean`](../actions/check-clean/README.md) when `check-clean` is `true`.
8. Upload of `artifacts`, also after a failure, as `<artifact-name>-<os>-node-<version>`.

The test framework writes the result and coverage files; the workflow only reads them. With
the Node test runner, for example:

```json
"test": "node --test --experimental-test-coverage --test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=test-results/junit.xml --test-reporter=lcov --test-reporter-destination=coverage/lcov.info"
```

```yaml
    with:
      test-results: test-results/junit.xml
      coverage-reports: coverage/lcov.info
      minimum-coverage: '80'
```

Vitest (`--reporter=junit`, `--coverage.reporter=cobertura`) and Jest (`jest-junit`,
`--coverageReporters=cobertura`) work the same way.

## Inputs

| Name | Default | Description |
|---|---|---|
| `working-directory` | `.` | Node project folder, relative to the repository root. |
| `node-versions` | `'["lts/*"]'` | Node versions as a JSON list. |
| `os` | `'["ubuntu-latest"]'` | Runner labels as a JSON list. |
| `package-manager` | detected | `npm`, `pnpm` or `yarn`. Empty detects it from the lockfile. |
| `scripts` | `test` | package.json scripts to run in order, separated by spaces. |
| `setup` | | package.json scripts run with `npm run` before the install. |
| `dependencies` | | Local Node projects it depends on, one per line; each is installed and built first. |
| `pre-build` | | Repository scripts run before the install, by path from the repository root, one per line. `.ps1` files run in PowerShell. |
| `post-build` | | Repository scripts run after the package.json scripts. |
| `browser` | `false` | Provide a system Chromium for browser tests (Linux runners install it with apt-get). |
| `test-results` | | JUnit, NUnit or TRX results files, relative to `working-directory`. Empty skips the report. |
| `coverage-reports` | | Cobertura, JaCoCo or LCOV reports, relative to `working-directory`. |
| `minimum-coverage` | `'0'` | Minimum line coverage percentage. |
| `check-clean` | `false` | Fail when the build changed or added files that are not ignored. |
| `check-clean-paths` | whole repository | Paths `check-clean` looks at, one per line. |
| `cache` | | setup-node dependency cache, `npm`. Empty turns caching off. |
| `cache-dependency-path` | | Lockfile for the cache key, from the repository root. Needed when the project is not at the root. |
| `artifacts` | | Files to upload, from the repository root, one per line. |
| `artifact-name` | `node-ci` | Artifact name prefix; the OS and Node version are appended. |
| `fetch-depth` | `1` | Commits to fetch; 0 fetches all history. |
| `submodules` | `false` | `true`, `recursive` or `false`. |
| `timeout-minutes` | `30` | Timeout of each test job. |

The workflow has no outputs.

## Permissions

`contents: read`.
