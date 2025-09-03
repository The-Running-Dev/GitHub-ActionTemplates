# Contributing to GitHub-ActionTemplates

Thank you for your interest in contributing to GitHub-ActionTemplates! This guide will help you get started with contributing to this project.

## 🤝 How to Contribute

### Types of Contributions

We welcome several types of contributions:

1. **New Templates**: Add templates for new frameworks, languages, or use cases
2. **Template Improvements**: Enhance existing templates with new features or optimizations
3. **Example Workflows**: Add more real-world usage examples
4. **Documentation**: Improve guides, add tutorials, or clarify existing docs
5. **Bug Fixes**: Fix issues in existing templates or documentation

### Getting Started

1. **Fork the Repository**
   ```bash
   git clone https://github.com/The-Running-Dev/GitHub-ActionTemplates.git
   cd GitHub-ActionTemplates
   ```

2. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make Your Changes**
   - Follow the existing structure and conventions
   - Test your changes thoroughly
   - Update documentation as needed

4. **Submit a Pull Request**
   - Provide a clear description of your changes
   - Include examples of how to use new features
   - Reference any related issues

## 📁 Repository Structure

When adding new content, follow this structure:

```
GitHub-ActionTemplates/
├── .github/
│   ├── templates/
│   │   ├── [category]/           # e.g., ci, build, deploy, test
│   │   │   └── [template].yml    # Reusable workflow template
│   │   └── sub-templates/        # Composite actions
│   │       └── [action].yml      # Reusable composite action
│   └── workflows/
│       └── example-workflows/    # Complete workflow examples
│           └── [framework].yml   # e.g., react-ci-cd.yml
└── docs/
    └── [guide].md               # Documentation files
```

## ✅ Template Guidelines

### Reusable Workflow Templates

1. **File Location**: Place in `.github/templates/[category]/`
2. **Naming**: Use descriptive names like `nodejs-ci.yml`, `python-test.yml`
3. **Structure**: Must use `workflow_call` trigger
4. **Inputs**: Define all configurable parameters with sensible defaults
5. **Documentation**: Include inline comments for complex logic

**Template Example**:
```yaml
name: Framework CI Pipeline

on:
  workflow_call:
    inputs:
      framework-version:
        description: 'Framework version to use'
        type: string
        default: 'latest'
      working-directory:
        description: 'Working directory'
        type: string
        default: '.'
    secrets:
      TOKEN:
        description: 'Authentication token'
        required: false

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      # Add your template logic here
```

### Composite Actions (Sub-Templates)

1. **File Location**: Place in `.github/templates/sub-templates/`
2. **Purpose**: Reusable steps that can be composed into workflows
3. **Structure**: Must use `composite` action type
4. **Naming**: Use verb-noun format like `setup-python.yml`

**Sub-Template Example**:
```yaml
name: 'Setup Framework Environment'
description: 'Reusable template for setting up framework with caching'

inputs:
  version:
    description: 'Framework version'
    required: false
    default: 'latest'

runs:
  using: 'composite'
  steps:
    - name: Setup Framework
      shell: bash
      run: |
        echo "Setting up framework version ${{ inputs.version }}"
```

### Example Workflows

1. **File Location**: Place in `.github/workflows/example-workflows/`
2. **Purpose**: Demonstrate real-world usage of templates
3. **Naming**: Use framework/use-case names like `django-api.yml`
4. **Content**: Show complete CI/CD pipeline using multiple templates

## 🧪 Testing Guidelines

### Template Validation

1. **YAML Syntax**: Ensure all YAML files are valid
   ```bash
   python3 -c "import yaml; yaml.safe_load(open('your-template.yml', 'r'))"
   ```

2. **GitHub Actions Validation**: Use GitHub's action validation
   ```bash
   # Install act for local testing (optional)
   curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
   ```

3. **Real Project Testing**: Test templates with actual projects
   - Create a sample project
   - Use your template in a workflow
   - Verify it works as expected

### Documentation Testing

1. **Links**: Verify all internal links work
2. **Examples**: Ensure all code examples are syntactically correct
3. **Clarity**: Have someone else review for clarity

## 📝 Documentation Standards

### Template Documentation

Each template should include:

1. **Header Comment**:
   ```yaml
   # Template: NodeJS CI Pipeline
   # Purpose: Complete CI pipeline for Node.js projects
   # Supports: npm, yarn, pnpm with caching and matrix builds
   ```

2. **Input Documentation**: Clear descriptions with examples
3. **Output Documentation**: If the template produces outputs
4. **Usage Examples**: Show common usage patterns

### README Updates

When adding new templates:

1. Update the template table in README.md
2. Add to the feature list if it's a new capability
3. Update roadmap if applicable

### Composition Examples

Add examples to `docs/composition-examples.md`:

1. **Basic Usage**: Simple, single-template examples
2. **Advanced Composition**: Multi-template workflows
3. **Real-World Scenarios**: Complete project examples

## 🎨 Code Style

### YAML Formatting

```yaml
# Use 2 spaces for indentation
name: Template Name

# Group related items
on:
  workflow_call:
    inputs:
      input-name:
        description: 'Clear description'
        type: string
        default: 'sensible-default'

# Use descriptive step names
jobs:
  job-name:
    runs-on: ubuntu-latest
    steps:
      - name: Clear, action-oriented step name
        uses: actions/checkout@v4
```

### Naming Conventions

- **Templates**: `kebab-case.yml` (e.g., `nodejs-ci.yml`)
- **Inputs**: `kebab-case` (e.g., `node-version`)
- **Jobs**: `kebab-case` (e.g., `run-tests`)
- **Steps**: Descriptive sentences (e.g., `Setup Node.js environment`)

### Comments

```yaml
# Template-level comments explain purpose and scope
name: Template Name

on:
  workflow_call:
    inputs:
      # Input comments explain usage and impact
      complex-input:
        description: 'What this does and when to use it'

jobs:
  job:
    steps:
      # Step comments for complex logic only
      - name: Complex operation
        run: |
          # Explain why this approach was chosen
          complex_command_here
```

## 🚀 Release Process

### Version Management

- Templates are versioned using Git tags
- Use semantic versioning for breaking changes
- Document breaking changes in release notes

### Compatibility

- Maintain backward compatibility when possible
- Clearly document any breaking changes
- Provide migration guides for major changes

## 📞 Getting Help

- **Questions**: Open a GitHub Discussion
- **Bugs**: Create a GitHub Issue with reproduction steps
- **Feature Requests**: Open a GitHub Issue with use case details

## 🏆 Recognition

Contributors are recognized in:
- Release notes for significant contributions
- README credits for major features
- GitHub contributor graphs

Thank you for helping make GitHub Actions workflows easier for everyone! 🎉