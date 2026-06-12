# Contributing to Vector Forge

Thank you for your interest in contributing to Vector Forge! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/vector-forge.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes
6. Commit with clear messages: `git commit -m "Add feature X"`
7. Push to your fork: `git push origin feature/your-feature-name`
8. Open a Pull Request

## Development Setup

### Prerequisites
- Python 3.11+
- Docker
- kubectl
- Terraform
- AWS CLI

### Local Development

```bash
# Set up Python environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
cd services/query-service
pip install -r requirements.txt

# Run locally
python -m src.main
```

### Testing

```bash
# Run linting
flake8 services/query-service/src
black services/query-service/src --check

# Run tests (when implemented)
pytest services/query-service/tests
```

## Project Structure

- `infrastructure/` - Terraform IaC
- `services/` - Application services
- `k8s/` - Kubernetes manifests
- `docs/` - Documentation

## Pull Request Guidelines

- Keep PRs focused on a single feature or fix
- Update documentation as needed
- Add tests for new functionality
- Ensure CI passes
- Follow existing code style

## Commit Message Format

```
type(scope): subject

body

footer
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

Example:
```
feat(query-service): add caching layer

Implement Redis caching for vector search results
to improve query latency.

Closes #123
```

## Questions?

Open an issue or reach out to the maintainers.
