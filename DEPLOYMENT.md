# Deployment

## Infrastructure

- **Host**: Hetzner VPS with [Dokku](https://dokku.com)
- **App name**: `wow-meta`
- **URL**: https://api.wowinsights.xyz
- **Container registry**: `ghcr.io/alessandro54/bis`

## CI/CD Pipeline

Automated deploys trigger on push to `main`:

1. **CI** (`ci.yml`) — runs RuboCop, Steep, and RSpec
2. **Build & Deploy** (`build-push.yml`) — triggers after CI passes:
   - Builds Docker image and pushes to GHCR (tagged `sha-<short>` + `latest`)
   - Deploys to Dokku via `git:from-image`

## Manual Deploy

### Via CI (preferred)

Merge to `main` and let the pipeline handle it.

### Via Dokku (direct)

```bash
# Push local branch directly (Dokku builds from source)
git push dokku develop:main --force
```

`--force` is always needed because Dokku's `git:from-image` (used by CI) creates synthetic commits that diverge from local git history.

### Via image (match CI behavior)

```bash
ssh dokku@<host> git:from-image wow-meta ghcr.io/alessandro54/bis:latest
```

## Environment Variables

```bash
# Set a variable (restarts app)
dokku config:set wow-meta KEY=value

# Set without restart
dokku config:set --no-restart wow-meta KEY=value

# List all
dokku config:show wow-meta
```

### Required

| Variable | Purpose |
|---|---|
| `BLIZZARD_CLIENT_ID` | Blizzard OAuth credentials |
| `BLIZZARD_CLIENT_SECRET` | Blizzard OAuth credentials |
| `WOW_BIS_DATABASE_PASSWORD` | PostgreSQL password |
| `SENTRY_DSN` | Sentry error tracking |

### Optional

| Variable | Default | Purpose |
|---|---|---|
| `BLIZZARD_CLIENT_ID_2` / `_SECRET_2` | — | Secondary Blizzard credentials (auth pool) |
| `RAILS_LOG_LEVEL` | `info` | Log verbosity |
| `DB_POOL` | `130` | PostgreSQL connection pool |
| `PVP_SYNC_BATCH_SIZE` | `50` | Characters per batch job |
| `PVP_SYNC_CONCURRENCY` | `15` | Thread concurrency in batch job |
| `PVP_SYNC_THREADS` | `8` | SolidQueue threads for character_sync |
| `PVP_BLIZZARD_RPS` | `95.0` | Blizzard API rate limit (req/sec) |
| `PVP_BLIZZARD_HOURLY_QUOTA` | `36000` | Blizzard API hourly cap |
| `SENTRY_TRACES_SAMPLE_RATE` | `0.1` | Sentry performance sampling (0-1) |

## Logs

```bash
# All processes
dokku logs wow-meta -t

# Web only
dokku logs wow-meta -p web

# Worker (background jobs)
dokku logs wow-meta -p worker
```

## Useful Commands

```bash
# Rails console
dokku run wow-meta bundle exec rails console

# Database migration
dokku run wow-meta bundle exec rails db:migrate

# Restart app
dokku ps:restart wow-meta

# Check running processes
dokku ps:report wow-meta
```

## Monitoring

- **Sentry**: Error tracking + performance tracing
- **Mission Control**: `/jobs` — SolidQueue job dashboard
- **Avo Admin**: `/avo` — data admin panel
- **Health check**: `/up`
