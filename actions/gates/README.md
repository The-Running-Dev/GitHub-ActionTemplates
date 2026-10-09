# gates

Checks that a repository's committed gates file lists the commands its CI runs, so a local
verification run (AgentKit's `/verify`, a pre-push script, a person) runs the same gates as CI.
[`node-ci.yml`](../../docs/node-ci.md), [`pwsh-ci.yml`](../../docs/pwsh-ci.md) and
[`npm-package.yml`](../../docs/npm-package.md) run it whenever the file exists. See
[docs/gates.md](../../docs/gates.md) for the file and how the gates are derived.

```yaml
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/gates@v0
```

With `write: true` it writes the file instead of checking it. A check that fails prints the
expected file in the log and the step summary, ready to commit.

## Inputs

| Name | Default | Description |
|---|---|---|
| `file` | `.github/gates.json` | Gates file, relative to the workspace. |
| `workflows` | `.github/workflows` | Folder of the workflows the gates are derived from. |
| `write` | `false` | Write the file instead of checking it. |
| `yaml-version` | `0.4.12` | powershell-yaml version used to read the workflows. |

## Outputs

| Name | Description |
|---|---|
| `status` | `match` when the file was checked, `written` when it was written. |
| `count` | Number of gates. |
