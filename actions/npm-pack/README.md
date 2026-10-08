# npm-pack

Packs a Node project into a tarball with `npm pack`, optionally stamping a computed version
into `package.json` first. Packing once and publishing that file means the tested build is
the published build. [`npm-package.yml`](../../docs/npm-package.md) packs in its build job
and publishes the tarball in a later job.

```yaml
- id: version
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/version@v0
  with:
    strategy: manifest

- id: pack
  uses: The-Running-Dev/GitHub-ActionTemplates/actions/npm-pack@v0
  with:
    version: ${{ steps.version.outputs.version }}

- uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
  with:
    name: npm-package
    path: ${{ steps.pack.outputs.tarball }}
```

- The version is stamped with `npm version --no-git-tag-version --ignore-scripts`: no commit,
  no tag, no version scripts. A leading `v` is removed.
- `npm pack` runs the `prepack`, `prepare` and `postpack` scripts unless `ignore-scripts` is
  set. Their output is shown in the log.

## Inputs

| Name | Default | Description |
|---|---|---|
| `path` | `.` | Node project folder, relative to the workspace. |
| `version` | | Version to stamp before packing. Empty keeps the package.json version. |
| `destination` | `dist-package` | Folder the tarball is written to, relative to the workspace. |
| `ignore-scripts` | `false` | Skip the pack lifecycle scripts, for a project built in an earlier step. |

## Outputs

| Name | Description |
|---|---|
| `tarball` | Tarball path, relative to the workspace. |
| `name` | Package name. |
| `version` | Package version. |
