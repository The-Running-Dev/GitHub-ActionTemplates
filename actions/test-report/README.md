# test-report

Summarises JUnit, NUnit 2, NUnit 3 and TRX test results in the job summary, with a table of
failed tests, and annotates the failures so they show on the run and the pull request.
It does not fail on failed tests unless asked, because the test step usually fails already.

```yaml
- run: npm test

- if: always()
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/test-report@v0
  with:
    results: test-results/*.xml
```

- Run it with `if: always()` so it reports after the test step failed.
- The format is read from the file's root element: `<testsuites>`/`<testsuite>` (JUnit),
  `<test-results>` (NUnit 2, Pester's `NUnitXml`), `<test-run>` (NUnit 3) and `<TestRun>` (TRX).
- At most 50 failures are listed and 10 annotated.
- No results found: a warning, or a failure with `fail-on-missing: true`.

## Inputs

| Name | Default | Description |
|---|---|---|
| `results` | required | Results files, relative to `working-directory`, one per line. Wildcards are allowed and `**/` searches folders. |
| `title` | `Tests` | Heading of the job summary section and the annotation title. |
| `fail-on-failure` | `false` | Fail the step when a test failed. |
| `fail-on-missing` | `false` | Fail the step when no results file is found. |
| `annotate` | `true` | Write an error annotation for each failed test. |
| `working-directory` | `.` | Folder the results paths are relative to, relative to the workspace. |

## Outputs

| Name | Description |
|---|---|
| `total` / `passed` / `failed` / `skipped` | Test counts across all files. |
