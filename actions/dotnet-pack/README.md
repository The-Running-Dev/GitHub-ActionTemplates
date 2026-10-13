# dotnet-pack

Packs a .NET solution into NuGet packages with a computed version, in a deterministic CI build
(`ContinuousIntegrationBuild`, which Source Link needs for reproducible paths).

```yaml
steps:
  - id: version
    uses: The-Running-Dev/GitHub-ActionTemplates/actions/version@v0
    with:
      strategy: manifest

  - id: pack
    uses: The-Running-Dev/GitHub-ActionTemplates/actions/dotnet-pack@v0
    with:
      version: ${{ steps.version.outputs.version }}

  - uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
    with:
      name: nuget-packages
      path: ${{ steps.pack.outputs.destination }}
```

Only projects with `IsPackable` true are packed; test projects usually set it false. The step
fails when no package is written, or when a package does not carry `version` because a project
sets `PackageVersion` itself.

## Inputs

| Name | Default | Description |
|---|---|---|
| `solution` | | Solution (.slnx, .sln) or project file, relative to `working-directory`. Empty uses the only solution in the folder, else the only project. |
| `working-directory` | `.` | Folder the command runs in, relative to the workspace. |
| `configuration` | `Release` | Build configuration. |
| `version` | | Package version (`-p:Version`); a leading `v` is dropped. Empty keeps the projects' version. |
| `args` | | Extra `dotnet pack` arguments, separated by spaces or new lines. |
| `enable-windows-targeting` | `false` | Set `EnableWindowsTargeting`, so Linux and macOS can pack `net*-windows` projects. |
| `destination` | `dist-nuget` | Folder for the packages, relative to the workspace. It is emptied first. |

## Outputs

| Name | Description |
|---|---|
| `packages` | The .nupkg and .snupkg files written, relative to the workspace, one per line. |
| `count` | Number of .nupkg files. |
| `destination` | The destination folder, relative to the workspace. |
