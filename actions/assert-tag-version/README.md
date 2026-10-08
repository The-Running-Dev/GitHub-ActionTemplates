# assert-tag-version

Fails a tag build when the tag does not match the version in the project manifest, so a release
cannot be published with the wrong number. On any other build it does nothing and reports
`checked=false`.

```yaml
- id: assert
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/assert-tag-version@v0
  with:
    manifest: src/MyLib/MyLib.csproj
```

The manifest is read the same way as the [`version`](../version/README.md) action's `manifest`
strategy: `package.json`, `Directory.Build.props`, a single `*.csproj`, a single `*.psd1`,
`Cargo.toml`, `pyproject.toml` or `VERSION`. MSBuild properties that use `$(...)` expressions
are rejected because they cannot be evaluated without a build.

## Inputs

| Name | Default | Description |
|---|---|---|
| `manifest` | auto-detected | Manifest path relative to `working-directory`. |
| `tag` | the current tag | Tag to check. When empty and the build is not for a tag, the check is skipped. |
| `tag-prefix` | `v` | Prefix of release tags. |
| `working-directory` | `.` | Directory with the manifest. |

## Outputs

| Name | Description |
|---|---|
| `checked` | `true` when a tag was compared, `false` when skipped. |
| `version` | The matching version; empty when skipped. |

On a mismatch the step fails with an error annotation on the manifest file.
