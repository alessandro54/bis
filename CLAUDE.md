# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Structure

This is a monorepo with two independent apps:
- `backend/` — Rails 8.1 API (Ruby 3.2)
- `frontend/` — Next.js 16 app (TypeScript, pnpm)

## Commands

All backend commands must be run from the `backend/` directory; frontend from `frontend/`.

### Backend (Rails)

```bash
# Development
bundle exec rails server

# Tests
bundle exec rspec                                     # full suite
bundle exec rspec spec/services/pvp/                  # specific directory
bundle exec rspec spec/jobs/pvp/sync_character_batch_job_spec.rb  # single file

# Linting
bundle exec rubocop
bundle exec rubocop --autocorrect

# Database
bundle exec rails db:create db:migrate
bundle exec rails db:schema:load  # faster for fresh setup
```

### Frontend (Next.js / pnpm)

```bash
pnpm install
pnpm dev       # runs on port 5123
pnpm build
pnpm lint
```

## Architecture

### What it does

WoW BIS tracks World of Warcraft PvP leaderboard data (US/EU, multi-region). It ingests character equipment and talent data from the Blizzard API, runs aggregations to compute PvP meta statistics (item popularity, talent builds, hero talents), and exposes the results through a Rails JSON API consumed by the Next.js frontend.

### Backend

**Multi-phase sync pipeline** (all jobs under `app/jobs/pvp/`):

1. `SyncCurrentSeasonLeaderboardsJob` — fetches all bracket leaderboards per region, collects character IDs
2. `SyncCharacterBatchJob` — processes characters concurrently using async fibers, enqueues entry processing
3. `ProcessLeaderboardEntryBatchJob` — runs `ProcessEquipmentService` and `ProcessSpecializationService` per entry
4. `BuildAggregationsJob` — triggered atomically when all batches complete; runs `ItemAggregationService` and `TalentAggregationService` per bracket

**Concurrency model** (`app/jobs/application_job.rb`): Jobs use `Async` gem (fiber-based, not threads). The `run_concurrently` helper wraps items in `Async::Semaphore`+`Async::Barrier`. `safe_concurrency` caps fiber count to `DB_POOL - 1` to prevent connection exhaustion. Concurrency is tunable via `PVP_SYNC_CONCURRENCY` (default: 5) and batch size via `PVP_SYNC_BATCH_SIZE` (default: 50).

**Service pattern** (`app/services/base_service.rb`): Services extend `BaseService`, are invoked via `.call(...)`, and return a `ServiceResult` with `#success?`, `#error`, `#payload`, and `#context`. Services live under `app/services/pvp/{characters,entries,leaderboards,meta}/` and `app/services/blizzard/`.

**Data storage optimizations**:
- Raw API responses (`raw_equipment`, `raw_specialization`) stored as bytea using `zstd-ruby` compression (~60% smaller)
- OJ used for fast JSON serialization/deserialization
- Query cache enabled in all jobs via `around_perform :with_query_cache`
- Atomic increments on `PvpSyncCycle` track batch completion without locking

**Blizzard API** (`app/services/blizzard/`): `Blizzard::Auth` manages OAuth tokens; `Blizzard::Client` wraps `httpx` for concurrent HTTP. API request classes live under `app/services/blizzard/api/`.

**Databases**: Multi-database Rails setup — primary app DB, plus separate SolidQueue, SolidCache, and SolidCable databases (all PostgreSQL).

**Job monitoring**: `JobPerformanceMonitor` records duration and success/failure for every job. Mission Control UI is mounted at `/jobs`.

**Domain data** (`app/lib/`): WoW game constants (classes, specs, roles, bracket configs) live under `app/lib/wow/` and `app/lib/pvp/`.

### Frontend

Next.js App Router with routes:
- `/dashboard` — main dashboard
- `/[classSlug]/[specSlug]/pvp/[bracket]/` — per-spec PvP stats
- `/meta/pvp/[bracket]/[role]/` — meta breakdown by bracket and role

UI uses Radix UI primitives, Tailwind CSS v4, and `next-themes` for dark mode. WoW class/spec configuration lives in `src/config/wow/`.

### API

Rails API-only app, versioned at `/api/v1/`. Routes are defined in `config/routes.rb`.
