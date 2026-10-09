# pwsh-check

Parses every PowerShell file (`.ps1`, `.psm1`, `.psd1`) and fails on syntax errors, so a
broken script fails the build before anything runs it. Optionally runs PSScriptAnalyzer too.
Each problem is annotated on its file and line, and the job summary lists them.
[`pwsh-ci.yml`](../../docs/pwsh-ci.md) runs it before Pester.

```yaml
- uses: The-Running-Dev/GitHub-ActionTemplates/actions/pwsh-check@v0
  with:
    paths: |
      src
      scripts
    exclude: src/vendor/*
    analyzer: true
    analyzer-settings: PSScriptAnalyzerSettings.psd1
```

- `.git` and `node_modules` folders are always skipped. `exclude` patterns match the
  workspace-relative path with `/` separators, so `vendor/*` skips everything under `vendor`.
- The parser needs no modules. The analyzer installs the pinned PSScriptAnalyzer version from
  the PowerShell Gallery when that version is not already installed.
- Without a settings file the analyzer reports `Error` and `Warning` findings from the default
  rules. A settings file decides everything itself (`Severity`, `ExcludeRules`, …).
- A folder with no PowerShell files warns rather than fails.

## Inputs

| Name | Default | Description |
|---|---|---|
| `paths` | `.` | Folders or files to check, relative to the workspace, one per line (or separated by `;`). |
| `exclude` | | Wildcard patterns of workspace-relative paths to skip, one per line. |
| `parse` | `true` | Parse each file and fail on syntax errors. |
| `analyzer` | `false` | Also run PSScriptAnalyzer and fail on any finding. |
| `analyzer-settings` | | PSScriptAnalyzer settings file, relative to the workspace. |
| `analyzer-version` | `1.25.0` | PSScriptAnalyzer version to install. |

## Outputs

| Name | Description |
|---|---|
| `files` | Number of files checked. |
| `errors` | Number of syntax errors and analyzer findings. |
