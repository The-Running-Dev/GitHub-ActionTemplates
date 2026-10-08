# GitHub-ActionTemplates

Reusable GitHub Actions workflows and composite actions for building, testing, versioning and
publishing projects. The goal is that a consuming repository's workflow is a few lines that
call a template, with every decision (version, publish or not, image name) made the same way
in every repository.

> **Status: 0.x.** The building-block actions below are usable now. The reusable workflows
> (npm, .NET, PowerShell module, Docker image, docs site) arrive in later 0.x releases, see
> [docs/PLAN.md](docs/PLAN.md). Inputs may still change before `v1.0.0`.

## Actions

| Action | What it does |
|---|---|
| [`version`](actions/version/README.md) | Computes a semantic version from git tags, a manifest file, or the run number. |
| [`assert-tag-version`](actions/assert-tag-version/README.md) | Fails a tag build when the tag and the manifest version differ. |
| [`context`](actions/context/README.md) | Normalises the run context: branch, slug, PR, tag, publish decision, image name. |
| [`debug`](actions/debug/README.md) | Prints the run context, runner, tool versions, disk space and workspace. |

The actions are PowerShell 7 composite actions and run on Linux, Windows and macOS runners.

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v7
        with:
          fetch-depth: 0 # the tag strategy reads the nearest tag
          persist-credentials: false

      - id: version
        uses: The-Running-Dev/GitHub-ActionTemplates/actions/version@v0

      - id: context
        uses: The-Running-Dev/GitHub-ActionTemplates/actions/context@v0

      - run: echo "Building ${{ steps.version.outputs.version }}"

      - if: steps.context.outputs.should-publish == 'true'
        run: echo "Publishing ${{ steps.context.outputs.image }}:${{ steps.version.outputs.version }}"
```

## Versioning and pinning

Releases are `vX.Y.Z` tags with notes from [CHANGELOG.md](CHANGELOG.md). Each release also
moves the major tag to the same commit:

| Pin | You get | Use when |
|---|---|---|
| `@v0` (`@v1` from 1.0) | Every compatible release automatically | Your own repositories, low ceremony |
| `@v0.1.0` | Exactly that release | You want to review every upgrade |
| `@<full commit SHA>` | Exactly that commit, immutable | Required by an SHA-pinning policy; let Dependabot bump it |

Within a major version, inputs and outputs are only added, never removed or renamed. Breaking
changes go to the next major.

Inside this repository, templates and actions refer to each other with the self-repository
syntax (`uses: $/actions/x`), so the pieces you get always come from the commit you pinned.

## Security

- Every workflow starts from `permissions: {}`; jobs ask only for what they need.
- Third-party actions are pinned to a full commit SHA and kept current by Dependabot with a
  seven-day cooldown.
- Checkouts use `persist-credentials: false`.
- Context values reach scripts through `env:`, never by `${{ }}` interpolation into `run:`.
- Every change is checked by [actionlint](https://github.com/rhysd/actionlint),
  [zizmor](https://github.com/zizmorcore/zizmor) and PSScriptAnalyzer.
- `debug` never prints a variable whose name contains TOKEN, SECRET, PASSWORD, KEY, CREDENTIAL
  or AUTH.

Report a vulnerability through the repository's **Security → Report a vulnerability** form, not a
public issue.

## Documentation

- [docs/conventions.md](docs/conventions.md): event semantics, version strategies, naming and
  security rules shared by every template.
- [docs/PLAN.md](docs/PLAN.md): the roadmap.
- [CONTRIBUTING.md](CONTRIBUTING.md): local setup, tests and the release process.

## License

[MIT](LICENSE)
