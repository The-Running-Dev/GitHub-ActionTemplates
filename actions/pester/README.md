# pester

Runs Pester 5 or 6 tests with a pinned Pester version, writes a test results file and, optionally,
a code coverage report. Fails when a test fails, when a test file cannot run (a syntax error
or a throwing `BeforeAll`), and when no tests ran at all.
[`pwsh-ci.yml`](../../docs/pwsh-ci.md) runs it on each operating system.

```yaml
- id: pester
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/pester@v0
  with:
    path: tests
    coverage: src
    exclude-tags: Integration

- if: always() && steps.pester.outputs.results != ''
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/test-report@v0
  with:
    results: ${{ steps.pester.outputs.results }}
```

- The Pester version is installed from the PowerShell Gallery unless it is already installed,
  then imported so the run cannot pick up another version on the runner.
- Zero tests is a failure by default, so a wrong `path` or tag filter cannot pass silently.
  Set `allow-empty: true` for a repository that has no tests yet.
- On GitHub Actions the output uses Pester's GitHub Actions format, which annotates failed tests.
- Outputs are set before the step fails, so a later `if: always()` step can still report them.

## Inputs

| Name | Default | Description |
|---|---|---|
| `path` | `tests` | Test folders or files, relative to the workspace, one per line (or separated by `;`). |
| `version` | `5.7.1` | Pester version to install (5.x or 6.x). |
| `tags` | | Run only tests with these tags, comma-separated. |
| `exclude-tags` | | Skip tests with these tags, comma-separated. |
| `results` | `test-results/pester.xml` | Test results file, relative to the workspace. Empty writes none. |
| `results-format` | `NUnitXml` | `NUnitXml` (NUnit 2.5), `NUnit3` (Pester 5.6+) or `JUnitXml`. |
| `coverage` | | Files or folders to measure coverage for, one per line. Empty turns coverage off. |
| `coverage-format` | `JaCoCo` | `JaCoCo`, `CoverageGutters`, or `Cobertura` (Pester 5.6+). |
| `coverage-output` | `coverage/pester-coverage.xml` | Coverage report file, relative to the workspace. |
| `allow-empty` | `false` | Pass when no tests ran. |

## Outputs

| Name | Description |
|---|---|
| `total` / `passed` / `failed` / `skipped` | Test counts. |
| `results` | Test results file, relative to the workspace; empty when none was written. |
| `coverage-report` | Coverage report file, relative to the workspace; empty when coverage is off. |
| `coverage` | Line coverage percentage reported by Pester; empty when coverage is off. |
