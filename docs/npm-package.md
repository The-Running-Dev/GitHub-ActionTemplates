# npm-package.yml

Tests and packs a Node package once, then publishes that same tarball and creates the GitHub
release.

| Run | Build, test, pack | Publish | GitHub release |
|---|---|---|---|
| Pull request | yes, version `1.2.3-pr.<PR>.<run>` | no | no |
| Push to the default branch | yes, version `1.2.3-ci.<run>` | only with `publish-prereleases`, under `next` | no |
| Tag `v1.2.3` | yes, version `1.2.3`; fails unless package.json says `1.2.3` | yes, under `latest` | yes |
| Push to another branch | yes | no | no |

The version comes from package.json ([`version`](../actions/version/README.md) with the
`manifest` strategy) and is stamped into the tarball, not committed.

| Job | Runs |
|---|---|
| `Build` | Checkout, Node, version, `pre-build`, install and `scripts`, `post-build`, [`npm-pack`](../actions/npm-pack/README.md), upload of the tarball. |
| `Publish` | [`npm-publish`](../actions/npm-publish/README.md) with the tarball from `Build`. |
| `GitHub release` | [`github-release`](../actions/github-release/README.md): notes from the tag's CHANGELOG section, tarball attached. Skipped when `Publish` failed. |

## Set up

1. Choose how the package is published:

   | Registry | Set up |
   |---|---|
   | npmjs, trusted publishing (recommended) | On npmjs.com, under the package's **Settings → Trusted publishing**, add GitHub Actions with the repository and **your** workflow file name (for example `release.yml`), not `npm-package.yml`. No secret needed. The first version must be published by hand or with a token. |
   | npmjs, token | Create an automation token and store it as the `NPM_TOKEN` repository secret. |
   | GitHub Packages | `registry: https://npm.pkg.github.com`. The package name must be scoped to the repository owner (`@owner/name`). No secret needed. |

2. Keep a `CHANGELOG.md` with a `## [x.y.z]` section for each release, or delete it to let
   GitHub generate the notes.
3. Add the workflow ([examples/npm-package.yml](../examples/npm-package.yml)):

```yaml
name: Package

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:

permissions: {}

jobs:
  package:
    permissions:
      contents: write
      packages: write
      id-token: write
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/npm-package.yml@v0
    with:
      access: public
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }} # omit with trusted publishing
```

The caller grants all three permissions even on pull requests, where only `Build` runs:
GitHub checks a reusable workflow's permissions before it runs any job. `Build` itself only
reads.

To release: set the version in package.json, add the CHANGELOG section, merge, then push the
tag (`git tag v1.2.3 && git push origin v1.2.3`).

## Inputs

| Name | Default | Description |
|---|---|---|
| `working-directory` | `.` | Package folder, relative to the repository root. |
| `node-version` | `lts/*` | Node version for the build and the publish. Trusted publishing needs npm 11.5.1+. |
| `package-manager` | detected | `npm`, `pnpm` or `yarn`. Empty detects it from the lockfile. |
| `scripts` | `test` | package.json scripts run before packing, separated by spaces. `npm pack` also runs `prepack`. |
| `setup` | | package.json scripts run with `npm run` before the install. |
| `pre-build` | | Repository scripts run before the install, by path from the repository root, one per line. |
| `post-build` | | Repository scripts run after the package.json scripts, before packing. |
| `publish` | `true` | Publish tag builds. `false` only builds and packs. |
| `publish-prereleases` | `false` | Also publish default-branch builds as prereleases under `next`. |
| `registry` | `https://registry.npmjs.org` | `https://npm.pkg.github.com` publishes to GitHub Packages. |
| `access` | | `public` or `restricted`. Empty uses the package.json `publishConfig` or the npm default. A new scoped package on npmjs needs `public`. |
| `provenance` | `true` | Publish with a provenance statement (npmjs and public repositories only). |
| `dist-tag` | | Empty uses `next` for prereleases and `latest` otherwise. |
| `github-release` | `true` | Create the GitHub release for a tag build. |
| `changelog` | `CHANGELOG.md` | CHANGELOG with the release notes, from the repository root. |
| `tag-prefix` | `v` | Prefix of release tags. |
| `artifact-name` | `npm-package` | Name of the tarball artifact. |
| `gates-file` | `.github/gates.json` | [Gates file](gates.md) checked against the workflows when it exists; empty turns the check off. |
| `fetch-depth` | `1` | Commits to fetch. |
| `submodules` | `false` | `true`, `recursive` or `false`. |
| `timeout-minutes` | `30` | Timeout of the build job. |

| Secret | Description |
|---|---|
| `NPM_TOKEN` | npm automation token. Without it npmjs uses trusted publishing and GitHub Packages uses `github.token`. |

## Outputs

| Name | Description |
|---|---|
| `version` | Package version that was built. |
| `published` | `true` when the package was published. |
| `release-url` | GitHub release URL, empty when no release was created. |
