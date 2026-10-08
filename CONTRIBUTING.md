# Contributing

Issues and pull requests are welcome. Before adding a template or action, read
[docs/conventions.md](docs/conventions.md); every piece follows the same rules for events,
versions, naming and security.

## Layout

```text
.github/workflows/   Reusable workflows (must be flat) and this repo's own CI
actions/<name>/      Composite actions: action.yml, <name>.ps1, README.md
actions/_lib/        Functions.psm1, shared by every action script
scripts/             Repository tooling (release notes)
tests/               Pester tests and fixtures/ (one sample project per manifest type)
docs/                Conventions and the roadmap
```

## Local setup

You need PowerShell 7.2 or later, plus:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser
```

actionlint and zizmor run in CI. To run them locally either install them or use Docker:

```bash
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12
docker run --rm -v "$PWD:/repo" -w /repo ghcr.io/zizmorcore/zizmor:1.30.1 --offline .
```

## Checks

```powershell
Invoke-Pester -Path tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Pull requests run the same checks on Linux, Windows and macOS (`lint.yml`, `self-test.yml`).
`self-test.yml` also runs every action from this checkout and asserts its outputs.

## Adding or changing an action

1. Put logic that more than one action could use in `actions/_lib/Functions.psm1`.
2. Map every input to an `INPUT_*` variable in `action.yml`; read it with `Get-ActionInput`.
3. Add Pester tests in `tests/` and a step in `self-test.yml`.
4. Document every input and output in the action's `README.md`.
5. Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).

Within a major version, only add inputs and outputs. Removing or renaming one, or changing a
default in a way that changes results, is a breaking change.

## Releasing (maintainers)

1. Move the `[Unreleased]` entries to a new `## [X.Y.Z] - YYYY-MM-DD` section and merge to `main`.
2. Tag the merge commit and push the tag:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

`release.yml` then runs lint and self-test again, checks that the tag is on `main`, creates the
GitHub release from the CHANGELOG section and moves the major tag (`v0`, `v1`) to the same commit.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) prefixes: `feat:`, `fix:`,
`docs:`, `ci:`, `test:`, `refactor:`, `chore:`. Mark breaking changes with `!` (`feat!:`).
