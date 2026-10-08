# run-scripts

Runs repository scripts by path, in order, and fails on the first one that fails. This is how
a workflow takes per-repository steps without putting script code in YAML: the caller passes
the path of a script it keeps in its own repository, and [`docs.yml`](../../docs/docs.md)
runs its `pre-build` and `post-build` inputs through this action.

```yaml
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/run-scripts@v0
  with:
    scripts: |
      ./build/Test-Documentation.ps1
      ./build/Test-SliceStatusMarkers.ps1
```

- `.ps1` files run in the step's PowerShell, with `$ErrorActionPreference = 'Stop'` and
  `$PSNativeCommandUseErrorActionPreference = $true`, so a failing native command inside the
  script fails it too.
- Any other file runs directly and must be executable (`chmod +x`, with a shebang).
- A script fails the step by throwing, by `exit` with a non-zero code, or by a native command
  that exits non-zero.
- Every path is checked before the first script runs. Paths must be inside the workspace.

Entries are paths only. Arguments and commands are rejected: put them in a script file.

## Inputs

| Name | Default | Description |
|---|---|---|
| `scripts` | required | Script paths relative to the workspace, one per line or separated by `;`. |
| `working-directory` | workspace | Folder the scripts run in, relative to the workspace. |
