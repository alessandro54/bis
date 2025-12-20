# GitHub Actions Workflows

This directory contains CI/CD workflows for the WoW BIS project.

## Workflows

### CI - Staging (`ci-staging.yml`)
- **Trigger**: Pull requests to `staging` branch
- **Jobs**:
  - **RuboCop**: Runs Ruby style linting
  - **RSpec**: Runs test suite with PostgreSQL
- **Features**:
  - PostgreSQL service for database tests
  - Ruby 3.2 with bundler cache
  - Node.js 20 for frontend assets
  - Coverage reporting with Codecov
  - Database setup and migration

### CI (`ci.yml`)
- **Trigger**: Push/PR to `main` and `develop` branches
- **Jobs**:
  - **Lint**: Runs RuboCop
  - **Test**: Runs RSpec with full environment
- **Features**: Same as staging workflow

## Environment Variables

The workflows use the following environment variables:

### Required
- `RAILS_ENV`: Set to `test`
- `DATABASE_URL`: PostgreSQL connection string
- `RAILS_MASTER_KEY`: From repository secrets (for staging)

### Optional
- Coverage reporting via Codecov (if configured)

## Setup

1. **Repository Secrets** (Required for staging):
   ```bash
   # In GitHub repository settings > Secrets and variables > Actions
   RAILS_MASTER_KEY=your_master_key_here
   ```

2. **Codecov** (Optional):
   - Sign up at [codecov.io](https://codecov.io)
   - Connect your repository
   - Get the upload token and add as `CODECOV_TOKEN` secret

## Workflow Triggers

### Staging Workflow
- Runs on: Pull requests to `staging` branch
- Events: `opened`, `synchronize`, `reopened`

### General CI Workflow
- Runs on: Push to `main`/`develop` branches
- Runs on: Pull requests to `main`/`develop` branches

## Local Testing

To test workflows locally:

```bash
# Install act for local GitHub Actions testing
brew install act

# Run staging workflow
act -j rubocop -W .github/workflows/ci-staging.yml
act -j rspec -W .github/workflows/ci-staging.yml

# Run general CI workflow
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

3. **Frontend Build Failures**
   - Ensure Node.js version matches
   - Check `package-lock.json` exists
   - Verify build scripts in `package.json`

4. **Secret Access Issues**
   - Ensure secrets are set in repository
   - Check workflow has access to secrets
   - Verify secret names match exactly

### Debugging

Enable debug logging by adding to workflow steps:

```yaml
- name: Debug info
  run: |
    echo "Ruby version: $(ruby --version)"
    echo "Bundler version: $(bundle --version)"
    echo "Node version: $(node --version)"
    echo "NPM version: $(npm --version)"
```

## Performance Optimizations

- **Caching**: Ruby gems and Node modules are cached
- **Parallel Jobs**: RuboCop and RSpec run in parallel
- **Database**: PostgreSQL service with health checks
- **Assets**: Frontend assets built once and reused

## Security

- **Secrets**: Sensitive data stored in repository secrets
- **Permissions**: Minimal required permissions
- **Dependencies**: Cached dependencies with integrity checks
