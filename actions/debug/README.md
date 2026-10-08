# debug

Prints what you need when a run behaves differently from your machine: the `GITHUB_*` and
`RUNNER_*` variables, tool versions (git, pwsh, node, npm, dotnet, docker, python), disk space
and the workspace contents, each in a collapsible log group.

```yaml
on:
  workflow_dispatch:
    inputs:
      debug:
        type: boolean
        default: false

# ...
      - uses: The-Running-Dev/GitHub-ActionTemplates/actions/debug@v0
        with:
          enabled: ${{ inputs.debug }}
```

Any variable whose name contains TOKEN, SECRET, PASSWORD, PASSWD, KEY, CREDENTIAL or AUTH is
left out entirely. The event payload is only printed with `include-event: true`; it can contain
user-supplied text such as PR titles, so leave it off for public repositories unless needed.

## Inputs

| Name | Default | Description |
|---|---|---|
| `enabled` | `true` | Set to `false` to skip, so the step can be wired to a `debug` input. |
| `include-event` | `false` | Also print the full event payload. |
