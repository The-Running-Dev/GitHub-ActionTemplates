# needs-gate

Fails when any job it needs failed or was cancelled. A matrix job reports one check per
combination (`Test (ubuntu-latest, 22)`), and those names change with the matrix; a final job
that runs this action gives the workflow one stable check to require in branch protection.

```yaml
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest]
    # ...

  result:
    name: Result
    needs: test
    if: always()
    runs-on: ubuntu-latest
    permissions: {}
    steps:
      - uses: The-Running-Dev/GitHub-ActionTemplates/actions/needs-gate@v0
        with:
          needs: ${{ toJSON(needs) }}
```

- The job needs `if: always()`; without it GitHub skips the job when a dependency fails, and a
  skipped required check counts as passing.
- Skipped dependencies pass by default, so a job skipped by its own `if:` does not block the
  gate. Set `allow-skipped: false` when every dependency must run.
- The job summary lists each dependency and its result.

## Inputs

| Name | Default | Description |
|---|---|---|
| `needs` | required | The `needs` context as JSON: `${{ toJSON(needs) }}`. |
| `allow-skipped` | `true` | Treat skipped jobs as passing. |

## Outputs

| Name | Description |
|---|---|
| `result` | `success` or `failure`. |
