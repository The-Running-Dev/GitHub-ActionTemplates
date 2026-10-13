# nuget-feed

Adds private NuGet feeds and their credentials to the NuGet config before a restore. The password
is written as `%NUGET_FEED_TOKEN%`, which NuGet reads from the environment when dotnet runs, so the
token is never on disk.

```yaml
permissions:
  contents: read
  packages: read # github.token reads GitHub Packages

steps:
  - uses: The-Running-Dev/GitHub-ActionTemplates/actions/nuget-feed@v0
    with:
      sources: github

  - run: dotnet restore
    env:
      NUGET_FEED_TOKEN: ${{ secrets.NUGET_FEED_TOKEN || github.token }}
```

## Sources

| Entry | Writes |
|---|---|
| `github` | Source `github` = `https://nuget.pkg.github.com/<owner>/index.json`, with credentials. |
| `name=url` | Source `name` = `url` (added, or its URL replaced), with credentials. |
| `name` | Credentials only, for a source the repository's nuget.config already defines. |

By default the user-level config is written (`%APPDATA%\NuGet\NuGet.Config` on Windows,
`~/.nuget/NuGet/NuGet.Config` elsewhere), which every project on the runner reads. A repository
nuget.config with `<clear />` in `packageSources` hides sources added there; list such sources by
name only, so they get credentials from the user config.

- `github.token` reads packages of the same owner once the package grants the repository access
  (package settings, **Manage Actions access**). Packages of another owner need a personal access
  token with `read:packages` in the `NUGET_FEED_TOKEN` secret.
- Feeds must use `https://`.

## Inputs

| Name | Default | Description |
|---|---|---|
| `sources` | `github` | Feeds, one per line (see above). |
| `username` | the run's actor | User name for the feeds. GitHub Packages accepts any name with a valid token. |
| `token-variable` | `NUGET_FEED_TOKEN` | Environment variable that holds the token when dotnet runs. |
| `config-file` | the user-level config | NuGet config to write instead, relative to the workspace. |

## Outputs

| Name | Description |
|---|---|
| `config-file` | Full path of the NuGet config that was written. |
