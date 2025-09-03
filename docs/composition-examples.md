# Template Composition Examples

This document provides practical examples of how to compose and customize GitHub Actions workflows using the templates provided in this repository.

## Table of Contents

- [Basic Composition](#basic-composition)
- [Advanced Compositions](#advanced-compositions)
- [Customization Patterns](#customization-patterns)
- [Template Reference](#template-reference)

## Basic Composition

### Simple CI Pipeline

```yaml
name: Simple CI

on: [push, pull_request]

jobs:
  ci:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/nodejs-ci.yml@main
    with:
      node-version: '18'
      package-manager: 'npm'
```

### Lint Only

```yaml
name: Lint Check

on: [pull_request]

jobs:
  lint:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/lint.yml@main
    with:
      node-version: '18'
      run-prettier: true
      run-type-check: true
```

### Build and Test

```yaml
name: Build and Test

on: [push]

jobs:
  test:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/test/coverage.yml@main
    with:
      upload-codecov: true
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
  
  build:
    needs: [test]
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/build/nodejs-build.yml@main
    with:
      build-output-dir: 'dist'
```

## Advanced Compositions

### Multi-Environment Pipeline

```yaml
name: Multi-Environment CI/CD

on:
  push:
    branches: [main, develop, staging]
  pull_request:
    branches: [main]

jobs:
  # Quality gates
  quality:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/nodejs-ci.yml@main
    with:
      node-version: '18'
      run-tests: true
      run-lint: true
      run-build: false

  # Matrix builds for different environments
  build:
    needs: [quality]
    strategy:
      matrix:
        environment: [development, staging, production]
        include:
          - environment: development
            build-command: 'npm run build:dev'
            node-env: 'development'
          - environment: staging
            build-command: 'npm run build:staging'
            node-env: 'staging'
          - environment: production
            build-command: 'npm run build:prod'
            node-env: 'production'
    
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/build/nodejs-build.yml@main
    with:
      build-command: ${{ matrix.build-command }}
      artifact-name: 'build-${{ matrix.environment }}'
      build-env: '{"NODE_ENV": "${{ matrix.node-env }}"}'

  # Environment-specific deployments
  deploy-dev:
    if: github.ref == 'refs/heads/develop'
    needs: [build]
    # Add deployment logic here

  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    needs: [build]
    # Add deployment logic here

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    needs: [build]
    # Add deployment logic here
```

### Monorepo Pipeline

```yaml
name: Monorepo CI/CD

on: [push, pull_request]

jobs:
  # Detect changes
  changes:
    runs-on: ubuntu-latest
    outputs:
      frontend: ${{ steps.changes.outputs.frontend }}
      backend: ${{ steps.changes.outputs.backend }}
      docs: ${{ steps.changes.outputs.docs }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v2
        id: changes
        with:
          filters: |
            frontend:
              - 'packages/frontend/**'
            backend:
              - 'packages/backend/**'
            docs:
              - 'docs/**'

  # Frontend pipeline
  frontend:
    if: needs.changes.outputs.frontend == 'true'
    needs: changes
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/nodejs-ci.yml@main
    with:
      working-directory: 'packages/frontend'
      node-version: '18'
      package-manager: 'npm'

  # Backend pipeline
  backend:
    if: needs.changes.outputs.backend == 'true'
    needs: changes
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/nodejs-ci.yml@main
    with:
      working-directory: 'packages/backend'
      node-version: '18'
      package-manager: 'npm'
      test-command: 'npm run test:unit && npm run test:integration'

  # Documentation pipeline
  docs:
    if: needs.changes.outputs.docs == 'true'
    needs: changes
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/build/nodejs-build.yml@main
    with:
      working-directory: 'docs'
      build-command: 'npm run build'
      build-output-dir: 'build'
```

## Customization Patterns

### Custom Package Managers

```yaml
# Using Yarn
jobs:
  ci:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/nodejs-ci.yml@main
    with:
      package-manager: 'yarn'
      test-command: 'yarn test'
      lint-command: 'yarn lint'
      build-command: 'yarn build'

# Using pnpm
jobs:
  ci:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/nodejs-ci.yml@main
    with:
      package-manager: 'pnpm'
      test-command: 'pnpm test'
      lint-command: 'pnpm lint'
      build-command: 'pnpm build'
```

### Matrix Testing

```yaml
jobs:
  test:
    strategy:
      matrix:
        node-version: ['16', '18', '20']
        os: [ubuntu-latest, windows-latest, macos-latest]
    
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/nodejs-ci.yml@main
    with:
      node-version: ${{ matrix.node-version }}
```

### Conditional Steps

```yaml
jobs:
  ci:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/nodejs-ci.yml@main
    with:
      run-tests: ${{ github.event_name == 'pull_request' }}
      run-build: ${{ github.ref == 'refs/heads/main' }}
      run-lint: true
```

### Custom Environment Variables

```yaml
jobs:
  build:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/build/nodejs-build.yml@main
    with:
      build-env: |
        {
          "NODE_ENV": "production",
          "API_URL": "https://api.example.com",
          "FEATURE_FLAGS": "advanced-mode,beta-features"
        }
```

## Template Reference

### Available Templates

| Template | Purpose | Key Inputs |
|----------|---------|------------|
| `templates/ci/nodejs-ci.yml` | Complete CI pipeline | `node-version`, `package-manager`, `run-tests`, `run-lint`, `run-build` |
| `templates/ci/lint.yml` | Linting only | `eslint-command`, `prettier-command`, `run-type-check` |
| `templates/test/coverage.yml` | Test with coverage | `test-command`, `upload-codecov`, `min-coverage` |
| `templates/build/nodejs-build.yml` | Build artifacts | `build-command`, `build-output-dir`, `artifact-name` |
| `templates/release/nodejs-release.yml` | Release management | `release-type`, `npm-publish`, `github-release` |

### Sub-Templates

| Sub-Template | Purpose | Key Inputs |
|--------------|---------|------------|
| `templates/sub-templates/setup-node.yml` | Node.js setup with caching | `node-version`, `cache`, `working-directory` |
| `templates/sub-templates/cache-deps.yml` | Dependency caching | `package-manager`, `cache-key` |

### Common Input Patterns

#### Node.js Version
```yaml
# Single version
node-version: '18'

# From file
node-version-file: '.nvmrc'

# Matrix (in your workflow, not template input)
strategy:
  matrix:
    node-version: ['16', '18', '20']
```

#### Package Managers
```yaml
package-manager: 'npm'    # Default
package-manager: 'yarn'
package-manager: 'pnpm'
```

#### Working Directory
```yaml
working-directory: '.'           # Default
working-directory: 'frontend'   # Monorepo package
working-directory: 'apps/web'   # Nested structure
```

#### Build Environment
```yaml
build-env: '{}'  # Default (empty)
build-env: '{"NODE_ENV": "production"}'  # Single variable
build-env: |     # Multiple variables
  {
    "NODE_ENV": "production",
    "API_URL": "https://api.prod.com",
    "BUILD_NUMBER": "${{ github.run_number }}"
  }
```

## Best Practices

### 1. Use Semantic Versioning
```yaml
release:
  uses: The-Running-Dev/GitHub-ActionTemplates/templates/release/nodejs-release.yml@main
  with:
    release-type: 'semantic'
```

### 2. Implement Quality Gates
```yaml
jobs:
  quality-gate:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/lint.yml@main
  
  test:
    needs: [quality-gate]
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/test/coverage.yml@main
  
  test:
    needs: [quality-gate]
    with:
      min-coverage: 80
  
  build:
    needs: [test]
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/build/nodejs-build.yml@main
```

### 3. Cache Dependencies
Templates automatically handle caching, but you can customize:
```yaml
# Automatic caching based on package manager
uses: The-Running-Dev/GitHub-ActionTemplates/templates/sub-templates/setup-node.yml@main
with:
  cache: 'npm'  # or 'yarn', 'pnpm'
```

### 4. Parallel Execution
```yaml
jobs:
  lint:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/ci/lint.yml@main
  
  test:
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/test/coverage.yml@main
  
  build:
    needs: [lint, test]  # Both must pass before building
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/build/nodejs-build.yml@main
  
  test:
    uses: ./.github/templates/test/coverage.yml
  
  build:
    needs: [lint, test]  # Both must pass before building
```

### 5. Environment-Specific Configurations
```yaml
jobs:
  build-prod:
    if: github.ref == 'refs/heads/main'
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/build/nodejs-build.yml@main
    with:
      build-command: 'npm run build:prod'
      build-env: '{"NODE_ENV": "production"}'
  
  build-dev:
    if: github.ref == 'refs/heads/develop'
    uses: The-Running-Dev/GitHub-ActionTemplates/templates/build/nodejs-build.yml@main
    with:
      build-command: 'npm run build:dev'
      build-env: '{"NODE_ENV": "development"}'
```