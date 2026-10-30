# dotnet.yml

Builds and tests a .NET solution on each runner in `os`, with a test report and an optional
coverage gate. With `pack`, it packs the NuGet packages once and publishes those same packages.

| Run | Build and test | Pack | Publish | GitHub release |
|---|---|---|---|---|
| Pull request | yes | version `1.2.3-pr.<PR>.<run>` | no | no |
| Push to the default branch | yes | version `1.2.3-ci.<run>` | only with `publish-prereleases` | no |
| Tag `v1.2.3` | yes | version `1.2.3`; fails unless the version source says `1.2.3` | yes | with `github-release` |
| Push to another branch | yes | yes | no | no |

Pack, Publish and GitHub release run only with `pack: true`. The version comes from
[`version`](../actions/version/README.md) with `version-strategy`: the `<Version>` in
Directory.Build.props or the project (`manifest`, the default), the tag (`tag`), the run number
(`run-number`) or [GitVersion](https://gitversion.net/) (`gitversion`, with GitVersion.Tool from
the repository's tool manifest when it lists one). It is passed to `dotnet pack` as `-p:Version`,
not committed.

| Job | Runs |
|---|---|
| `Test (<os>)` | Checkout, .NET, feeds, `pre-build`, [`dotnet-test`](../actions/dotnet-test/README.md) (restore, build, test), test report, coverage gate, `post-build`, upload of the results. |
| `Pack` | Checkout, .NET, version, feeds, `pre-build`, [`dotnet-pack`](../actions/dotnet-pack/README.md), upload of the packages. |
| `Publish` | [`nuget-push`](../actions/nuget-push/README.md) with the packages from `Pack`, after NuGet/login for trusted publishing. One at a time per repository. |
| `Post-publish` | `post-publish` scripts, with `PACKAGE_VERSION`. |
| `GitHub release` | [`github-release`](../actions/github-release/README.md): notes from the tag's CHANGELOG section, packages attached. Skipped when `Publish` failed. |
| `Result` | [`needs-gate`](../actions/needs-gate/README.md): the one check for branch protection to require, `<caller job> / Result`. |

## Set up

1. Pick the SDK: a `global.json` at the repository root, or `dotnet-version` (`10.0.x`, one per
   line for several). Without either, the SDK on the runner is used.
2. For private feeds, list them in `nuget-sources` (see [`nuget-feed`](../actions/nuget-feed/README.md)).
   `github.token` reads GitHub Packages of the same owner once each package grants the
   repository access (package settings, **Manage Actions access**). Packages of another owner
   need a personal access token with `read:packages` as the `NUGET_FEED_TOKEN` secret.
3. With `pack`, choose where the packages go:

   | Feed | Set up |
   |---|---|
   | GitHub Packages (`nuget-source: github`, the default) | No secret needed. |
   | nuget.org, trusted publishing (recommended) | On nuget.org, add a trusted publishing policy for the repository and **your** workflow file (for example `release.yml`), not `dotnet.yml`. Set `nuget-user` to the nuget.org account, and `environment` when the policy names one. |
   | nuget.org or another feed, API key | `nuget-source: nuget.org` or the feed URL; store the key as the `NUGET_API_KEY` secret. |

4. With `github-release`, keep a `CHANGELOG.md` with a `## [x.y.z]` section for each release.
5. Add the workflow ([examples/dotnet.yml](../examples/dotnet.yml)):

```yaml
name: .NET

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:

permissions: {}

jobs:
  dotnet:
    permissions:
      contents: write
      packages: write
      id-token: write
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/dotnet.yml@v1
    with:
      os: '["ubuntu-latest", "windows-latest"]'
      coverage: true
      minimum-coverage: '60'
      pack: true
      github-release: true
```

The caller grants every permission the workflow's jobs ask for, even on pull requests where only
`Test` and `Pack` run, and even without `pack`: GitHub checks the permissions of every job,
including the publish and release jobs that will be skipped, before it runs any job. A caller
that grants less fails with `startup_failure`.

Windows-only solutions (WPF, WinForms) set `os: '["windows-latest"]'`, or keep Linux runners with
`enable-windows-targeting: true` when the tests do not need Windows.

To release: set the version, add the CHANGELOG section, merge, then push the tag
(`git tag v1.2.3 && git push origin v1.2.3`).

## Inputs

| Name | Default | Description |
|---|---|---|
| `os` | `["ubuntu-latest"]` | JSON list of runners to build and test on. |
| `dotnet-version` | | SDK versions for actions/setup-dotnet, one per line. Empty uses `global-json-file`, else the SDK on the runner. |
| `global-json-file` | `global.json` | global.json that pins the SDK, used when it exists. |
| `working-directory` | `.` | Folder with the solution, relative to the repository root. |
| `solution` | | Solution or project file in `working-directory`. Empty finds the only .slnx, .sln or project file there. |
| `configuration` | `Release` | Build configuration. |
| `enable-windows-targeting` | `false` | Build `net*-windows` projects on Linux and macOS runners. |
| `restore-args` | | Extra `dotnet restore` arguments. |
| `build-args` | | Extra `dotnet build` arguments. |
| `test` | `true` | Run `dotnet test`. `false` only builds. |
| `test-args` | | Extra `dotnet test` arguments. |
| `test-filter` | | `dotnet test --filter` expression, for example `Category!=Integration`. |
| `coverage` | `false` | Collect coverage with coverlet; each test project needs coverlet.collector. Reports of several test projects are merged. |
| `minimum-coverage` | `0` | Minimum line coverage in percent; 0 reports coverage without failing. |
| `nuget-sources` | | Private feeds that need credentials, one per line: `name=url`, `name`, or `github`. |
| `pre-build` | | Repository scripts run before the restore in `Test` and `Pack`, by path from the repository root, one per line. |
| `post-build` | | Repository scripts run after the tests. |
| `artifact-name` | `dotnet-test` | Name prefix of the test results artifact; the runner is appended. |
| `retention-days` | `7` | Days to keep the artifacts. |
| `pack` | `false` | Pack the NuGet packages after the tests pass, and publish them per `publish`. |
| `pack-os` | first of `os` | Runner that packs. |
| `pack-args` | | Extra `dotnet pack` arguments. |
| `version-strategy` | `manifest` | `manifest`, `tag`, `run-number` or `gitversion`. |
| `manifest` | | Manifest with the version, relative to `working-directory`. Empty finds it. |
| `base-version` | | Major.Minor for the `run-number` strategy. |
| `tag-prefix` | `v` | Prefix of release tags. |
| `prerelease-label` | `ci` | Prerelease label of builds that are not tag builds. |
| `gitversion-version` | `6.8.2` | GitVersion.Tool version, when the repository has no tool manifest for it. |
| `package-artifact-name` | `nuget-packages` | Name of the packages artifact. |
| `publish` | `true` | Publish the packages from tag builds. `false` only packs. |
| `publish-prereleases` | `false` | Also publish default-branch builds as prereleases. |
| `nuget-source` | `github` | `github`, `nuget.org`, or a feed URL. |
| `nuget-user` | | nuget.org account for trusted publishing. Empty uses the `NUGET_API_KEY` secret. |
| `environment` | | Environment `Publish` runs in, for approvals and environment secrets. |
| `skip-duplicate` | `true` | Treat a version already on the feed as published, so a re-run passes. |
| `post-publish` | | Repository scripts run after publishing; they get `PACKAGE_VERSION` and `NUGET_FEED_TOKEN`. |
| `github-release` | `false` | Create the GitHub release for a tag build, with the packages attached. |
| `changelog` | `CHANGELOG.md` | CHANGELOG with the release notes, from the repository root. |
| `gates-file` | `.github/gates.json` | [Gates file](gates.md) checked against the workflows when it exists; empty turns the check off. |
| `fetch-depth` | `1` | Commits to fetch. The `tag` and `gitversion` strategies fetch all history to pack. |
| `submodules` | `false` | `true`, `recursive` or `false`. |
| `timeout-minutes` | `30` | Timeout of the test and pack jobs. |
| `utility-runs-on` | `ubuntu-latest` | Runner for the Publish, GitHub release and Result jobs. A self-hosted Linux label keeps private repositories off hosted minutes. |

| Secret | Description |
|---|---|
| `NUGET_FEED_TOKEN` | Token for `nuget-sources`. Without it `github.token` is used. |
| `NUGET_API_KEY` | API key for `nuget-source`. Not needed for GitHub Packages or with `nuget-user`. |

## Outputs

| Name | Description |
|---|---|
| `version` | Package version that was packed, empty without `pack`. |
| `published` | `true` when the packages were published. |
| `release-url` | GitHub release URL, empty when no release was created. |
