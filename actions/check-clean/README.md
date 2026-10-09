# check-clean

Fails when the build changed the working tree: generated files that were not committed, a
lockfile the install rewrote, or a formatter that changed sources. Untracked files count as
changes; ignored files do not.

```yaml
- run: npm run generate

- uses: The-Running-Dev/GitHub-ActionTemplates/actions/check-clean@v0
  with:
    paths: src/generated
```

The changed files are listed in the log (with `git diff --stat`) and in the job summary. The
fix is to run the same build locally and commit the result.

## Inputs

| Name | Default | Description |
|---|---|---|
| `paths` | whole repository | Paths to check, relative to the workspace, one per line. |

## Outputs

| Name | Description |
|---|---|
| `clean` | `true` when there are no changes. |
