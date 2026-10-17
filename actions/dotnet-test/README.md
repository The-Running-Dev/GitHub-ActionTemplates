# dotnet-test

Restores, builds and tests a .NET solution, writing TRX results for
[test-report](../test-report) and, with `coverage`, one merged Cobertura report for
[coverage-gate](../coverage-gate). The [.NET workflow](../../docs/dotnet.md) uses it on every runner.

```yaml
steps:
  - uses: actions/setup-dotnet@a98b56852c35b8e3190ac28c8c2271da59106c68 # v6.0.0
    with:
      dotnet-version: 10.0.x

  - id: test
    uses: The-Running-Dev/GitHub-ActionTemplates/actions/dotnet-test@v1
    with:
      filter: Category!=Integration
      coverage: 'true'

  - if: ${{ !cancelled() && steps.test.outputs.results != '' }}
    uses: The-Running-Dev/GitHub-ActionTemplates/actions/test-report@v1
    with:
      results: ${{ steps.test.outputs.results }}

  - if: steps.test.outputs.coverage-report != ''
    uses: The-Running-Dev/GitHub-ActionTemplates/actions/coverage-gate@v1
    with:
      reports: ${{ steps.test.outputs.coverage-report }}
      minimum: 60
```

It runs `dotnet restore`, `dotnet build --no-restore` and `dotnet test --no-build`, so a restore
or compile error is reported on its own line. A failing test run still sets the outputs before the
step fails, so the report steps after it see the results.

- Coverage uses coverlet's `XPlat Code Coverage` collector: each test project needs the
  `coverlet.collector` package. Coverlet writes one report per test project; they are merged by
  file and line into `<results-directory>/coverage.cobertura.xml`, so a line two test projects
  cover is counted once.
- Private feeds: add credentials first with [nuget-feed](../nuget-feed) and set the token variable
  on this step.

## Inputs

| Name | Default | Description |
|---|---|---|
| `solution` | | Solution (.slnx, .sln) or project file, relative to `working-directory`. Empty uses the only solution in the folder, else the only project. |
| `working-directory` | `.` | Folder the commands run in, relative to the workspace. |
| `configuration` | `Release` | Build configuration. |
| `restore-args` / `build-args` / `test-args` | | Extra arguments for each command, separated by spaces or new lines. Double quotes keep an argument with spaces together. |
| `test` | `true` | `false` only restores and builds. |
| `filter` | | `dotnet test --filter` expression. |
| `coverage` | `false` | Collect line coverage with coverlet. |
| `enable-windows-targeting` | `false` | Set `EnableWindowsTargeting`, so Linux and macOS runners can build `net*-windows` projects. |
| `results-directory` | `TestResults` | Folder for the results, relative to the workspace. It is emptied first. |

## Outputs

| Name | Description |
|---|---|
| `results` | TRX files relative to the workspace (`TestResults/*.trx`), empty when no tests ran. |
| `coverage-report` | The merged Cobertura report, empty without coverage. |
| `solution` | The solution or project that was built, relative to the workspace. |
