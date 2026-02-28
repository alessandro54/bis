# WoW BIS — PvP Meta API

Rails API that tracks World of Warcraft PvP leaderboard data for US and EU regions. It fetches character equipment and talent data from the Blizzard API, aggregates it into PvP meta statistics (item/enchant/gem popularity, talent builds, class distribution), and serves the results as a JSON API.

## Prerequisites

- Ruby 4.0.1 (via [rbenv](https://github.com/rbenv/rbenv) or [mise](https://mise.jdx.dev))
- PostgreSQL 14+
- Bundler (`gem install bundler`)
- Blizzard developer credentials ([register an app](https://develop.battle.net/access/clients))

## Local Setup

### 1. Clone and install dependencies

```bash
git clone <repo-url>
cd bis
bundle install
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and set at minimum:

```bash
# Required — Blizzard OAuth app credentials
BLIZZARD_CLIENT_ID=your_client_id
BLIZZARD_CLIENT_SECRET=your_client_secret

# Optional — second credential pair for auth pool redundancy
# BLIZZARD_CLIENT_ID_2=your_second_client_id
# BLIZZARD_CLIENT_SECRET_2=your_second_client_secret
```

All other values in `.env.example` have sane defaults for local development.

### 3. Set up databases

The app uses four PostgreSQL databases: primary app data, SolidQueue jobs, SolidCache, and SolidCable. Rails manages all of them.

```bash
bundle exec rails db:create db:migrate
```

Or for a faster fresh setup (skips migrations, loads schema directly):

```bash
bundle exec rails db:schema:load
```

### 4. Start the server

```bash
bundle exec rails server
```

The API is available at `http://localhost:3000`.

### 5. Start the job worker (optional, for running the sync pipeline)

In a separate terminal:

```bash
bundle exec rails solid_queue:start
```

> Without the worker, the API still serves existing data — you just won't be able to trigger new syncs.

## Running a Sync

The sync pipeline is triggered manually (no cron scheduler in development). Use the Rails console or the Avo admin panel.

```bash
bundle exec rails console
```

```ruby
# You need at least one current PvpSeason record
PvpSeason.create!(name: "Season 1", blizzard_id: 37, is_current: true, display_name: "Season 1")

# Full sync: discovers all brackets for US+EU, fetches all characters, builds aggregations
Pvp::SyncCurrentSeasonLeaderboardsJob.perform_later

# Ad-hoc single bracket (no sync cycle tracking)
Pvp::SyncBracketJob.perform_later(region: "us", season: PvpSeason.current, bracket: "3v3")
```

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `BLIZZARD_CLIENT_ID` | — | **Required.** Blizzard OAuth client ID |
| `BLIZZARD_CLIENT_SECRET` | — | **Required.** Blizzard OAuth client secret |
| `BLIZZARD_CLIENT_ID_2` | — | Optional second client for auth pool |
| `BLIZZARD_CLIENT_SECRET_2` | — | Optional second client secret |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_POOL` | `130` | Connection pool size (20 is fine locally) |
| `PVP_SYNC_BATCH_SIZE` | `50` | Characters processed per batch job |
| `PVP_SYNC_CONCURRENCY` | `15` | Thread concurrency within a batch job |
| `PVP_SYNC_THREADS` | `8` | SolidQueue threads for character sync workers |
| `PVP_LEADERBOARD_CONCURRENCY` | `10` | Concurrent Blizzard leaderboard fetches |
| `PVP_BLIZZARD_RPS` | `95.0` | Blizzard API rate limit (requests/sec) |
| `PVP_BLIZZARD_HOURLY_QUOTA` | `36000` | Blizzard API hourly request cap |
| `PVP_META_TOP_N` | `1000` | Top N entries used in meta aggregations |
| `RAILS_MAX_THREADS` | `3` | Puma thread count |

## API Endpoints

All endpoints return JSON. No authentication required.

```
GET /up                                      # Health check
GET /api/v1/characters                       # Character list
GET /api/v1/pvp/meta/items                  # Item popularity stats
GET /api/v1/pvp/meta/enchants               # Enchant popularity stats
GET /api/v1/pvp/meta/gems                   # Gem popularity stats
GET /api/v1/pvp/meta/specs                  # Spec distribution
GET /api/v1/pvp/meta/specs/:id              # Single spec stats
GET /api/v1/pvp/meta/class_distribution     # Class distribution
```

## Admin & Monitoring

- **Job monitor** — `http://localhost:3000/jobs` (Mission Control UI for SolidQueue)
- **Admin panel** — `http://localhost:3000/avo` (Avo resource management)

## Tests

```bash
bundle exec rspec                           # full suite
bundle exec rspec spec/jobs/                # job specs only
bundle exec rspec spec/services/pvp/        # PvP service specs
bundle exec rspec spec/requests/            # API integration specs
```

Linting and type checking:

```bash
bundle exec rubocop
bundle exec rubocop --autocorrect
bundle exec steep check
```

## Architecture Overview

```
Blizzard API
     │
     ▼
SyncCurrentSeasonLeaderboardsJob      ← Phase 1: discover brackets, sync leaderboards
     │  (per region, parallel HTTP)
     ▼
SyncCharacterBatchJob ×N              ← Phase 2: fetch character equipment + talents
     │  (threaded, region-isolated queues)
     ▼
BuildAggregationsJob                  ← Phase 3: compute meta stats per bracket
     │  (triggered atomically when all batches complete)
     ▼
PostgreSQL (pvp_meta_* tables)
     │
     ▼
JSON API (/api/v1/pvp/meta/*)
```