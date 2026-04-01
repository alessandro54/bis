# GitHub Actions Workflows

This directory contains CI/CD workflows for the WoW BIS project.

## Workflows

### CI (`ci.yml`)
- **Trigger**: Push to `main`, PRs to `develop`
- **Jobs**:
  - **Lint**: Runs RuboCop and Steep
  - **Test**: Runs RSpec with PostgreSQL
- **Features**:
  - PostgreSQL service for database tests
  - Ruby 4.0 with bundler cache
  - Coverage reporting with Codecov

## Environment Variables

### Required
- `RAILS_ENV`: Set to `test`
- `DATABASE_URL`: PostgreSQL connection string

### Optional
- Coverage reporting via Codecov (if configured)

## Workflow Triggers

- Push to `main` branch
- Pull requests to `develop` branch

## Local Testing

```bash
# Install act for local GitHub Actions testing
brew install act

# Run CI workflow
act -j lint -W .github/workflows/ci.yml
act -j test -W .github/workflows/ci.yml
```

## Troubleshooting

### Common Issues

1. **Database Connection Errors**
   - Ensure PostgreSQL service is healthy
   - Check `DATABASE_URL` format
   - Verify database exists and is accessible

2. **Bundle Install Failures**
   - Check Ruby version compatibility
   - Verify `Gemfile.lock` is up to date
   - Clear cache if needed

### Debugging

Enable debug logging by adding to workflow steps:

```yaml
- name: Debug info
  run: |
    echo "Ruby version: $(ruby --version)"
    echo "Bundler version: $(bundle --version)"
```

## Performance Optimizations

- **Caching**: Ruby gems cached via bundler-cache
- **Parallel Jobs**: Lint and Test run in parallel
- **Database**: PostgreSQL service with health checks

## Security

- **Secrets**: Sensitive data stored in repository secrets
- **Permissions**: Minimal required permissions
- **Dependencies**: Cached dependencies with integrity checks
