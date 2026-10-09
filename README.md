# GitHub-ActionTemplates

Reusable GitHub Actions workflows and composite actions for building, testing, versioning and
publishing projects. The goal is that a consuming repository's workflow is a few lines that
call a template, with every decision (version, publish or not, image name) made the same way
in every repository.

> **Status: 0.x.** The workflows and actions below are usable now. More reusable workflows
> (.NET, Docker image, static sites) arrive in later 0.x releases, see
> [docs/PLAN.md](docs/PLAN.md). Inputs may still change before `v1.0.0`.

## Workflows

| Workflow | What it does |
|---|---|
| [`docs.yml`](docs/docs.md) | Builds a Docusaurus site and deploys it to GitHub Pages from the default branch and tags. |
| [`node-ci.yml`](docs/node-ci.md) | Runs a Node project's scripts on an OS × Node matrix, with test report, coverage gate and clean-tree check. |
| [`pwsh-ci.yml`](docs/pwsh-ci.md) | Syntax-checks PowerShell files, optionally runs PSScriptAnalyzer, and runs Pester with coverage on each OS. |
| [`npm-package.yml`](docs/npm-package.md) | Tests and packs an npm package, publishes it from tags (npmjs or GitHub Packages) and creates the GitHub release. |

```yaml
jobs:
  docs:
    permissions: { contents: read, pages: write, id-token: write }
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/workflows/docs.yml@v0
```

Complete caller workflows are in [examples/](examples).

## Actions

| Action | What it does |
|---|---|
| [`version`](actions/version/README.md) | Computes a semantic version from git tags, a manifest file, or the run number. |
| [`assert-tag-version`](actions/assert-tag-version/README.md) | Fails a tag build when the tag and the manifest version differ. |
| [`context`](actions/context/README.md) | Normalises the run context: branch, slug, PR, tag, publish decision, image name. |
| [`debug`](actions/debug/README.md) | Prints the run context, runner, tool versions, disk space and workspace. |
| [`docs-build`](actions/docs-build/README.md) | Builds a Docusaurus site from a bundled template or the folder's own Node project. |
| [`run-scripts`](actions/run-scripts/README.md) | Runs repository scripts by path, in order, failing on the first failure. |
| [`changelog`](actions/changelog/README.md) | Writes a Markdown changelog page from the git history, with pull request links. |
| [`node-scripts`](actions/node-scripts/README.md) | Installs a Node project and runs its scripts in order, after building its local dependencies; optionally provides Chromium. |
| [`pwsh-check`](actions/pwsh-check/README.md) | Parses PowerShell files for syntax errors and optionally runs PSScriptAnalyzer, annotating each problem. |
| [`pester`](actions/pester/README.md) | Runs Pester 5 or 6 at a pinned version with results and coverage; fails when no tests ran. |
| [`test-report`](actions/test-report/README.md) | Summarises JUnit, NUnit and TRX results in the job summary and annotates failures. |
| [`coverage-gate`](actions/coverage-gate/README.md) | Combines Cobertura, JaCoCo and LCOV coverage and fails below a minimum. |
| [`check-clean`](actions/check-clean/README.md) | Fails when the build changed or added files that are not ignored. |
| [`needs-gate`](actions/needs-gate/README.md) | Fails when a needed job failed: one stable required check for a matrix. |
| [`npm-pack`](actions/npm-pack/README.md) | Packs a Node project into a tarball, optionally stamping a computed version. |
| [`npm-publish`](actions/npm-publish/README.md) | Publishes a tarball to npmjs or GitHub Packages with provenance and a dist-tag from the version. |
| [`github-release`](actions/github-release/README.md) | Creates or updates the GitHub release for a tag with CHANGELOG notes and attachments. |
| [`gates`](actions/gates/README.md) | Checks the committed [gates file](docs/gates.md) against the commands the workflows run. |

The actions are PowerShell 7 composite actions and run on Linux, Windows and macOS runners
(`docs-build` with the `template` builder runs in the build-agent container).

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

- [docs/docs.md](docs/docs.md): the documentation workflow.
- [docs/node-ci.md](docs/node-ci.md), [docs/pwsh-ci.md](docs/pwsh-ci.md),
  [docs/npm-package.md](docs/npm-package.md): the Node, PowerShell and npm package workflows.
- [docs/conventions.md](docs/conventions.md): event semantics, version strategies, naming and
  security rules shared by every template.
- [docs/PLAN.md](docs/PLAN.md): the roadmap.
- [CONTRIBUTING.md](CONTRIBUTING.md): local setup, tests and the release process.

## License

[MIT](LICENSE)
