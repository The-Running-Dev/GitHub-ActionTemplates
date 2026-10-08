# coverage-gate

Reads line coverage from Cobertura, JaCoCo and LCOV reports, writes a table to the job
summary, and fails when the combined coverage is below a minimum. With the default minimum
of `0` it only reports.

```yaml
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/coverage-gate@v0
  with:
    minimum: 80
```

- The default `reports` finds `coverage.cobertura.xml`, `cobertura-coverage.xml`,
  `cobertura.xml`, `jacoco.xml`, `pester-coverage.xml` and `lcov.info` anywhere under
  `working-directory` (`node_modules` and `.git` are skipped).
- Several reports are combined by adding their covered and coverable lines, so the result is
  the coverage of all the code they measured, not an average of percentages.
- The format is read from the file: `<coverage>` is Cobertura, `<report>` is JaCoCo, and
  `SF:`/`LF:`/`LH:` lines are LCOV. Any other file fails the step.
- No report found: a warning when `minimum` is `0`, a failure otherwise.

## Inputs

| Name | Default | Description |
|---|---|---|
| `reports` | the usual report names | Report files, relative to `working-directory`, one per line. Wildcards are allowed and `**/` searches folders. |
| `minimum` | `0` | Minimum line coverage percentage (0–100). `0` only reports. |
| `title` | `Coverage` | Heading of the job summary section. |
| `working-directory` | `.` | Folder the report paths are relative to, relative to the workspace. |

## Outputs

| Name | Description |
|---|---|
| `coverage` | Combined line coverage percentage, rounded to two decimals; empty when no report was found. |
| `covered` / `total` | Covered and coverable lines across all reports. |
| `passed` | `true` when coverage meets the minimum. |
