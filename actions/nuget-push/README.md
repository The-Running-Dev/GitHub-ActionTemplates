# nuget-push

Pushes NuGet packages to GitHub Packages, nuget.org or another feed. With `skip-duplicate` a version
that is already on the feed counts as pushed, so a re-run of a release passes.

```yaml
permissions:
  contents: read
  packages: write # GitHub Packages
  id-token: write # nuget.org trusted publishing

steps:
  - id: login
    uses: NuGet/login@8d196754b4036150537f80ac539e15c2f1028841 # v1.2.0
    with:
      user: ${{ vars.NUGET_USER }}

  - uses: The-Running-Dev/GitHub-ActionTemplates/actions/nuget-push@v1
    with:
      packages: dist-nuget/*.nupkg
      source: nuget.org
      api-key: ${{ steps.login.outputs.NUGET_API_KEY }}
```

## Authentication

| Feed | `api-key` | Set up |
|---|---|---|
| GitHub Packages (`github`) | `${{ github.token }}` | The job needs `packages: write`. |
| nuget.org, trusted publishing | the NuGet/login output | Add a trusted publishing policy on nuget.org for the repository and the **calling** workflow file. The job needs `id-token: write`. |
| nuget.org, API key | an API key secret | Store a key scoped to the packages as a secret. |

The key is passed to `dotnet nuget push` and masked in the log.

- Symbol packages (.snupkg) next to a .nupkg are pushed with it to nuget.org. GitHub Packages has
  no symbol server, so they are left out there.
- Feeds must use `https://`.

## Inputs

| Name | Default | Description |
|---|---|---|
| `packages` | `dist-nuget/*.nupkg` | .nupkg files relative to the workspace, one per line. Wildcards and `**/` are allowed. |
| `source` | `github` | `github` (GitHub Packages of the repository owner), `nuget.org`, or a feed URL. |
| `api-key` | | API key or token for the feed. |
| `skip-duplicate` | `true` | Treat a version already on the feed as pushed. |
| `symbols` | `true` | `false` leaves out .snupkg files. |
| `dry-run` | `false` | List the pushes without running them. |

## Outputs

| Name | Description |
|---|---|
| `published` | `true` when the packages were pushed; `false` for a dry run. |
| `count` | Number of .nupkg files. |
| `source` | Feed URL the packages went to. |
