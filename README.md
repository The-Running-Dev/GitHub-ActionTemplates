# GitHub-ActionTemplates

A comprehensive collection of reusable GitHub Actions workflow templates for rapid CI/CD pipeline setup across various project types, starting with NodeJS frameworks like React, Angular, Docusaurus, and more.

## 🚀 Overview

This repository provides flexible and composable GitHub Actions templates that enable you to quickly assemble tailored CI/CD workflows for your projects. Instead of writing workflows from scratch, you can leverage these battle-tested templates and focus on your application logic.

## ✨ Features

- **🧩 Composable Templates**: Mix and match workflow components to build custom pipelines
- **📦 NodeJS Optimized**: Built-in support for npm, yarn, and pnpm with smart caching
- **🔄 Reusable Workflows**: Leverage `workflow_call` for maximum flexibility
- **🎯 Framework Examples**: Ready-to-use examples for React, Angular, Docusaurus
- **📊 Quality Gates**: Integrated linting, testing, and coverage reporting
- **🚢 Release Automation**: Semantic versioning and automated releases
- **📚 Comprehensive Docs**: Detailed guides and composition examples

## 📁 Repository Structure

```
GitHub-ActionTemplates/
├── README.md                               # This file
├── .github/
│   ├── workflows/
│   │   └── example-workflows/              # Example workflows using templates
│   │       ├── react-ci-cd.yml            # React app pipeline
│   │       ├── angular-ci-cd.yml          # Angular app pipeline
│   │       └── docusaurus-ci-cd.yml       # Docusaurus site pipeline
│   └── templates/
│       ├── ci/
│       │   ├── nodejs-ci.yml              # Complete NodeJS CI pipeline
│       │   └── lint.yml                   # Linting workflow
│       ├── test/
│       │   └── coverage.yml               # Test coverage workflow
│       ├── build/
│       │   └── nodejs-build.yml           # Build artifacts workflow
│       ├── release/
│       │   └── nodejs-release.yml         # Release management workflow
│       └── sub-templates/
│           ├── setup-node.yml             # Node.js environment setup
│           └── cache-deps.yml             # Dependency caching
└── docs/
    └── composition-examples.md             # Detailed composition guide
```

## 🚀 Quick Start

### 1. Basic CI Pipeline

Create `.github/workflows/ci.yml` in your project:

```yaml
name: CI

on: [push, pull_request]

jobs:
  ci:
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/ci/nodejs-ci.yml@main
    with:
      node-version: '18'
      package-manager: 'npm'
```

### 2. Complete CI/CD Pipeline

```yaml
name: CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  # Quality checks
  lint:
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/ci/lint.yml@main
    with:
      node-version: '18'
      run-type-check: true

  test:
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/test/coverage.yml@main
    with:
      upload-codecov: true
    secrets:
      CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}

  # Build
  build:
    needs: [lint, test]
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/build/nodejs-build.yml@main
    with:
      build-command: 'npm run build'
      artifact-name: 'production-build'

  # Release (on main branch only)
  release:
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    needs: [build]
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/release/nodejs-release.yml@main
    with:
      release-type: 'semantic'
      github-release: true
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## 📋 Available Templates

### Core Templates

| Template | Purpose | Use Case |
|----------|---------|----------|
| **`ci/nodejs-ci.yml`** | Complete CI pipeline | Full CI with lint, test, build |
| **`ci/lint.yml`** | Code quality checks | ESLint, Prettier, TypeScript |
| **`test/coverage.yml`** | Test execution with coverage | Unit tests, coverage reports |
| **`build/nodejs-build.yml`** | Build artifacts | Production builds, Docker images |
| **`release/nodejs-release.yml`** | Release management | Semantic releases, NPM publishing |

### Sub-Templates (Composite Actions)

| Sub-Template | Purpose | Use Case |
|--------------|---------|----------|
| **`sub-templates/setup-node.yml`** | Node.js environment setup | Standardized Node.js setup with caching |
| **`sub-templates/cache-deps.yml`** | Dependency caching | Custom caching strategies |

## 🎯 Framework Examples

Check out the [`example-workflows`](.github/workflows/example-workflows/) directory for complete pipeline examples:

- **[React CI/CD](.github/workflows/example-workflows/react-ci-cd.yml)**: Complete pipeline with staging/production deployments
- **[Angular CI/CD](.github/workflows/example-workflows/angular-ci-cd.yml)**: Multi-environment builds with E2E testing
- **[Docusaurus CI/CD](.github/workflows/example-workflows/docusaurus-ci-cd.yml)**: Documentation site with GitHub Pages deployment

## 🔧 Configuration Options

### Common Inputs

#### Node.js Configuration
```yaml
with:
  node-version: '18'              # Node.js version
  node-version-file: '.nvmrc'     # Or read from file
  package-manager: 'npm'          # npm, yarn, or pnpm
  working-directory: '.'          # For monorepos
```

#### Build Configuration
```yaml
with:
  build-command: 'npm run build'
  build-output-dir: 'dist'
  artifact-name: 'my-build'
  build-env: '{"NODE_ENV": "production"}'
```

#### Test Configuration
```yaml
with:
  test-command: 'npm test'
  coverage-path: 'coverage'
  min-coverage: 80
  upload-codecov: true
```

#### Release Configuration
```yaml
with:
  release-type: 'semantic'        # or 'manual'
  github-release: true
  npm-publish: false
  pre-release: false
```

### Package Manager Support

All templates support multiple package managers:

```yaml
# NPM (default)
package-manager: 'npm'

# Yarn
package-manager: 'yarn'

# pnpm
package-manager: 'pnpm'
```

## 🏗️ Advanced Usage

### Monorepo Support

```yaml
jobs:
  frontend:
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/ci/nodejs-ci.yml@main
    with:
      working-directory: 'packages/frontend'
      
  backend:
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/ci/nodejs-ci.yml@main
    with:
      working-directory: 'packages/backend'
```

### Matrix Builds

```yaml
jobs:
  test:
    strategy:
      matrix:
        node-version: ['16', '18', '20']
        os: [ubuntu-latest, windows-latest]
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/ci/nodejs-ci.yml@main
    with:
      node-version: ${{ matrix.node-version }}
```

### Conditional Workflows

```yaml
jobs:
  build-dev:
    if: github.ref == 'refs/heads/develop'
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/build/nodejs-build.yml@main
    with:
      build-command: 'npm run build:dev'
      
  build-prod:
    if: github.ref == 'refs/heads/main'
    uses: The-Running-Dev/GitHub-ActionTemplates/.github/templates/build/nodejs-build.yml@main
    with:
      build-command: 'npm run build:prod'
```

## 📚 Documentation

- **[Composition Examples](docs/composition-examples.md)**: Detailed examples of composing workflows
- **[Template Reference](docs/composition-examples.md#template-reference)**: Complete input/output documentation
- **[Best Practices](docs/composition-examples.md#best-practices)**: Recommended patterns and configurations

## 🤝 Contributing

We welcome contributions! Whether you want to:

- Add new templates for other frameworks/languages
- Improve existing templates
- Add more example workflows
- Enhance documentation

Please feel free to open an issue or submit a pull request.

### Development Setup

1. Fork the repository
2. Create templates in the appropriate directories
3. Add example workflows demonstrating usage
4. Update documentation
5. Test with real projects

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙋‍♂️ Support

- **Issues**: Report bugs or request features via [GitHub Issues](https://github.com/The-Running-Dev/GitHub-ActionTemplates/issues)
- **Discussions**: Ask questions in [GitHub Discussions](https://github.com/The-Running-Dev/GitHub-ActionTemplates/discussions)
- **Documentation**: Check our [composition examples](docs/composition-examples.md) for detailed usage

## 🗺️ Roadmap

- [ ] Python/Django templates
- [ ] Java/Spring Boot templates  
- [ ] .NET Core templates
- [ ] Docker-based workflows
- [ ] Kubernetes deployment templates
- [ ] AWS/Azure/GCP deployment workflows
- [ ] Security scanning templates
- [ ] Performance testing workflows

---

**Made with ❤️ for the developer community**