# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

Standalone Rails API-only app (Rails 8.1, Ruby 4.0.1). Frontend lives in a separate repository. All commands run from the repo root.

## Commands

```bash
# Development
bundle exec rails server

# Tests
bundle exec rspec                                                          # full suite
bundle exec rspec spec/services/pvp/                                      # directory
bundle exec rspec spec/jobs/pvp/sync_character_batch_job_spec.rb          # single file

# Linting & type checking
bundle exec rubocop
bundle exec rubocop --autocorrect
bundle exec steep check

# Database
bundle exec rails db:create db:migrate
bundle exec rails db:schema:load   # faster for fresh setup
```

## Architecture

### What it does

WoW BIS tracks World of Warcraft PvP leaderboard data (US/EU). It ingests character equipment and talent data from the Blizzard API, runs aggregations to compute PvP meta statistics (item/enchant/gem popularity, talent builds, class distribution), and exposes results via a versioned JSON API at `/api/v1/`.

### Sync Pipeline

Four-phase pipeline, all jobs under `app/jobs/pvp/`:

1. **`SyncCurrentSeasonLeaderboardsJob`** — orchestrator; creates a `PvpSyncCycle`, discovers brackets for US+EU concurrently, calls `SyncLeaderboardService` per bracket, then enqueues `SyncCharacterBatchJob` batches to region-isolated queues (`character_sync_us`, `character_sync_eu`).
2. **`SyncCharacterBatchJob`** — processes a batch of characters concurrently via threads; calls `SyncCharacterService` per character; atomically increments `PvpSyncCycle#completed_character_batches` and triggers `BuildAggregationsJob` when all batches finish.
3. **`BuildAggregationsJob`** — runs `ItemAggregationService`, `EnchantAggregationService`, `GemAggregationService`, and `ClassDistributionService` per bracket.
4. **`SyncBracketJob`** — standalone single-bracket sync (no sync cycle), for ad-hoc/manual use.

`Characters::SyncCharacterMetaBatchJob` runs separately to refresh character metadata (class, spec, media).

### Concurrency Model

Jobs use two concurrency mechanisms:
- **Threads** (`run_with_threads`): used for Blizzard HTTP calls (leaderboard discovery, character sync batches). `safe_concurrency` caps to `THREADS - 1` to prevent DB pool exhaustion.
- **Fibers** (`run_concurrently`, Async gem): available via `ApplicationJob` helpers but currently threads are preferred for HTTP work.

Tunable via env vars: `PVP_SYNC_CONCURRENCY` (default 15), `PVP_SYNC_THREADS` (default 8), `PVP_SYNC_BATCH_SIZE` (default 50), `PVP_LEADERBOARD_CONCURRENCY` (default 10).

### Service Pattern

All services extend `BaseService`, are called via `.call(...)`, and return a `ServiceResult` with `#success?`, `#failure?`, `#error`, `#payload`, `#context`. Services live under:
- `app/services/pvp/characters/` — character sync
- `app/services/pvp/leaderboards/` — leaderboard sync
- `app/services/pvp/entries/` — equipment/specialization processing
- `app/services/pvp/meta/` — aggregation SQL + services
- `app/services/blizzard/` — API client, auth, rate limiter

### Blizzard API

`Blizzard::Auth` manages OAuth tokens; `Blizzard::AuthPool` supports multiple client credentials for redundancy. `Blizzard::Client` wraps `httpx` for concurrent HTTP. Rate limiter enforces `PVP_BLIZZARD_RPS` (default 95.0 rps) and `PVP_BLIZZARD_HOURLY_QUOTA` (default 36,000).

### Data Storage

- Raw API responses (`raw_equipment`, `raw_specialization`) stored as `bytea` using `zstd-ruby` compression (~60% smaller)
- `oj` gem used for all JSON (via `Oj.optimize_rails` + `Oj.mimic_JSON` in initializer)
- Query cache enabled in all jobs via `around_perform :with_query_cache`
- `PvpSyncCycle` uses atomic DB increments to track batch completion without locking

### Databases (all PostgreSQL)

Multi-database Rails setup:
- `primary` — app data
- `queue` — SolidQueue backend
- `cache` — SolidCache backend (256MB max)
- `cable` — SolidCable backend

### Queue Configuration (`config/queue.yml`)

Production workers are region-isolated:
- `character_sync_us` / `character_sync_eu` — one dedicated worker per region (`PVP_SYNC_THREADS` threads each)
- Bracket queues (`pvp_sync_2v2`, `pvp_sync_3v3`, `pvp_sync_shuffle`, `pvp_sync_rbg`) — shared worker
- `pvp_processing` + catchall — shared worker

Set `QUEUE_PROFILE=low_resource` for a single-worker low-thread profile.

### Domain Constants (`app/lib/`)

- `Pvp::SyncConfig` — `EQUIPMENT_TTL` (1 hour), `META_TTL` (1 week)
- `Pvp::RegionConfig` — `REGIONS`, `REGION_QUEUES`, `REGION_LOCALES` for US/EU
- `Pvp::BracketConfig` — per-bracket settings: `top_n`, `rating_min`, `job_queue`
- `Wow::Catalog` — all 40 specs mapped to class/role; `Wow::Classes`, `Wow::Specs`, `Wow::Roles`

### Key Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `BLIZZARD_CLIENT_ID` / `_SECRET` | — | Blizzard OAuth credentials (required) |
| `BLIZZARD_CLIENT_ID_2` / `_SECRET_2` | — | Secondary Blizzard credentials (auth pool) |
| `DB_POOL` | 130 | PostgreSQL connection pool size |
| `DB_HOST` / `DB_PORT` | localhost/5432 | PostgreSQL host/port |
| `WOW_BIS_DATABASE_PASSWORD` | — | Production DB password |
| `PVP_SYNC_BATCH_SIZE` | 50 | Characters per batch job |
| `PVP_SYNC_CONCURRENCY` | 15 | Fiber/thread concurrency in batch job |
| `PVP_SYNC_THREADS` | 8 | SolidQueue threads for character_sync workers |
| `PVP_LEADERBOARD_CONCURRENCY` | 10 | Concurrent leaderboard HTTP fetches |
| `PVP_BLIZZARD_RPS` | 95.0 | Blizzard API requests per second |

### Admin & Monitoring

- Mission Control job UI: `/jobs`
- Avo admin panel: `/avo`
- `JobPerformanceMonitor` records duration and success/failure for every job

### API Routes

```
GET /up                                      # health check
GET /api/v1/characters
GET /api/v1/pvp/meta/items
GET /api/v1/pvp/meta/enchants
GET /api/v1/pvp/meta/gems
GET /api/v1/pvp/meta/specs
GET /api/v1/pvp/meta/specs/:id
GET /api/v1/pvp/meta/class_distribution
```

### Testing

RSpec + FactoryBot + DatabaseCleaner (truncation between suite runs, transaction per test). Fixtures for Blizzard API responses live in `spec/fixtures/`. SimpleCov tracks coverage.

```bash
bundle exec rspec spec/jobs/
bundle exec rspec spec/services/pvp/
bundle exec rspec spec/requests/
```
