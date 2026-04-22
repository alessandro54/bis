# Sync Observability, Integrity & Blue-Green Cycles — Design Spec

## Goal

Eliminate silent failures in the PvP sync pipeline by wiring Sentry coverage at every failure point, guaranteeing atomic character sync, protecting live aggregation data with a blue-green promotion strategy, and automatically recovering characters that fail to sync.

## Architecture

Four independent but sequenced concerns:

1. **Sentry hooks** — additive, touches `ApplicationJob` + `BaseService` only
2. **Character sync transaction** — wraps equipment + specialization in a single DB transaction
3. **Recovery job** — detects null-timestamp entries and re-queues them before aggregation
4. **Blue-green aggregation** — `pvp_sync_cycle_id` FK on popularity tables, live cycle promotion on success

Parts 2 and 3 are prerequisites for Part 4. Part 1 is independent.

## Tech Stack

Ruby on Rails 8, ActiveRecord, Sidekiq, Sentry (`sentry-rails`), PostgreSQL.

---

## Part 1 — Sentry Coverage

### Problem

Only one explicit `Sentry.capture_exception` call exists in the entire codebase (`SyncCurrentSeasonLeaderboardsJob:106`). Every `ServiceResult.failure(e)` and every unhandled job exception is logged locally but never captured.

### Design

**`ApplicationJob` (`app/jobs/application_job.rb`)**

Inside `monitor_performance`'s rescue block (currently re-raises without capturing), add:

```ruby
Sentry.capture_exception(e, extra: { job: self.class.name, job_id: job_id, args: arguments.to_s.truncate(500) })
```

Before the existing `raise`. This covers every job exception automatically.

**`BaseService` (`app/services/base_service.rb`)**

In `failure(error, message:, payload:, context:)`, add Sentry capture when `error` is an exception:

```ruby
def failure(error, message: nil, payload: nil, context: {})
  if error.is_a?(Exception)
    Sentry.capture_exception(error, extra: { service: self.class.name }.merge(context))
  end
  ServiceResult.failure(error, message: message, payload: payload, context: context)
end
```

This covers every `ServiceResult.failure(e)` across the entire codebase — `SyncBracketJob`, `BuildAggregationsJob`, `SyncCharacterService`, all aggregation services — with zero per-service changes.

### Testing

- `application_job_spec.rb`: assert `Sentry.capture_exception` called when job raises
- `base_service_spec.rb`: assert Sentry called on `failure(StandardError.new(...))`, not called on `failure("string error")`

---

## Part 2 — Character Sync Transaction

### Problem

`SyncCharacterService` calls `ProcessEquipmentService` then `ProcessSpecializationService` sequentially with no wrapping transaction. If equipment succeeds (sets `equipment_processed_at`) but spec fails, the entry has equipment data but stale/null `specialization_processed_at` — inconsistent state that is invisible until queried.

### Design

In `app/services/pvp/characters/sync_character_service.rb`, wrap the two service calls:

```ruby
ApplicationRecord.transaction do
  result = ProcessEquipmentService.new(entry, character_data).call
  raise ActiveRecord::Rollback unless result.success?

  result = ProcessSpecializationService.new(entry, character_data).call
  raise ActiveRecord::Rollback unless result.success?
end
```

Both succeed → both timestamps written. Either fails → both rolled back → `equipment_processed_at` and `specialization_processed_at` remain null. Clean failure state, no partial data.

**Precondition**: `ProcessEquipmentService` and `ProcessSpecializationService` must not have side effects outside this transaction (e.g. external API calls). Confirm they only write to DB — they do (both only update `pvp_leaderboard_entries` and related character tables).

### Testing

- `sync_character_service_spec.rb`: stub `ProcessEquipmentService` to succeed, `ProcessSpecializationService` to fail → assert neither timestamp is written
- Inverse: both succeed → both timestamps written

---

## Part 3 — Recovery Job

### Problem

Characters that fail to sync (null `equipment_processed_at` or `specialization_processed_at`) remain permanently incomplete. There is no mechanism to detect and re-queue them.

### Design

**Schema change** — add to `pvp_leaderboard_entries`:

```ruby
add_column :pvp_leaderboard_entries, :sync_retry_count, :integer, default: 0, null: false
```

**New job** — `app/jobs/pvp/recover_failed_character_syncs_job.rb`:

```ruby
class Pvp::RecoverFailedCharacterSyncsJob < ApplicationJob
  MAX_RETRIES = 3
  BATCH_SIZE  = 100

  def perform(pvp_sync_cycle_id)
    cycle   = PvpSyncCycle.find(pvp_sync_cycle_id)
    season  = cycle.pvp_season
    entries = unsynced_entries(season)

    if entries.none?
      BuildAggregationsJob.perform_later(pvp_sync_cycle_id)
      return
    end

    exhausted = entries.where(sync_retry_count: MAX_RETRIES)
    if exhausted.any?
      Sentry.capture_message(
        "Characters exhausted sync retries",
        extra: { season_id: season.id, count: exhausted.count,
                 character_ids: exhausted.limit(50).pluck(:character_id) },
        level: :warning
      )
    end

    recoverable = entries.where(sync_retry_count: ...MAX_RETRIES)
    recoverable.in_batches(of: BATCH_SIZE) do |batch|
      batch.update_all("sync_retry_count = sync_retry_count + 1")
      SyncCharacterBatchJob.perform_later(batch.pluck(:character_id))
    end
  end

  private

    def unsynced_entries(season)
      PvpLeaderboardEntry
        .joins(:pvp_leaderboard)
        .where(pvp_leaderboards: { pvp_season_id: season.id })
        .where("equipment_processed_at IS NULL OR specialization_processed_at IS NULL")
    end
end
```

**Cycle wiring** — in `SyncCharacterBatchJob#track_sync_cycle_completion`, replace direct `BuildAggregationsJob.perform_later` with `RecoverFailedCharacterSyncsJob.perform_later(cycle.id)`. Recovery job enqueues aggregation when no unsynced entries remain.

**Retry loop mechanics**: When recovery job finds recoverable entries, it:
1. Increments `pvp_sync_cycle.expected_character_batches` by the number of new recovery batches
2. Enqueues `SyncCharacterBatchJob` batches normally
3. Those batches complete → `track_sync_cycle_completion` fires → counter matches → enqueues `RecoverFailedCharacterSyncsJob` again

Each pass increments `sync_retry_count`. After `MAX_RETRIES` passes an entry is exhausted and skipped. When `RecoverFailedCharacterSyncsJob` finds zero recoverable entries (all synced or exhausted), it breaks the loop by enqueueing `BuildAggregationsJob` directly instead of more batches.

### Testing

- `recover_failed_character_syncs_job_spec.rb`:
  - All entries synced → enqueues `BuildAggregationsJob`, no `SyncCharacterBatchJob`
  - Recoverable entries exist → increments `sync_retry_count`, enqueues batches
  - Exhausted entries → Sentry warning with character IDs
  - Mix of exhausted + recoverable → warns on exhausted, re-queues recoverable

---

## Part 4 — Blue-Green Aggregation Cycles

### Problem

Each aggregation service runs `delete_all` then `insert_all!`. If aggregation fails halfway, live data is gone. No "rollback to last good data" is possible.

### Design

**Schema changes:**

```ruby
# Add cycle reference to all 4 popularity tables
add_reference :pvp_meta_item_popularity,    :pvp_sync_cycle, null: true, index: true
add_reference :pvp_meta_enchant_popularity, :pvp_sync_cycle, null: true, index: true
add_reference :pvp_meta_gem_popularity,     :pvp_sync_cycle, null: true, index: true
add_reference :pvp_meta_talent_popularity,  :pvp_sync_cycle, null: true, index: true

# Live cycle pointer on season
add_reference :pvp_seasons, :live_pvp_sync_cycle, null: true,
              foreign_key: { to_table: :pvp_sync_cycles }
```

**Aggregation service changes** (`ItemAggregationService`, `EnchantAggregationService`, `GemAggregationService`, `TalentAggregationService`):

- Accept `cycle:` kwarg in `initialize`
- Change `insert_all!` records to include `pvp_sync_cycle_id: cycle.id`
- Remove `delete_all` — do NOT delete existing rows

**`BuildAggregationsJob` changes:**

```ruby
def perform(pvp_sync_cycle_id)
  cycle   = PvpSyncCycle.find(pvp_sync_cycle_id)
  season  = cycle.pvp_season
  results = run_aggregations(cycle)

  if results.all?(&:success?)
    promote_cycle(season, cycle)
  else
    rollback_draft(cycle)
    Sentry.capture_message("Aggregation cycle failed — live data preserved",
      extra: { cycle_id: cycle.id, failures: results.reject(&:success?).map(&:error).map(&:message) })
  end
end

private

  def promote_cycle(season, cycle)
    ApplicationRecord.transaction do
      old_cycle_id = season.live_pvp_sync_cycle_id
      season.update!(live_pvp_sync_cycle_id: cycle.id)
      purge_old_cycle_data(old_cycle_id) if old_cycle_id
    end
    Rails.cache.delete_matched("pvp_meta/*")
  end

  def rollback_draft(cycle)
    [PvpMetaItemPopularity, PvpMetaEnchantPopularity,
     PvpMetaGemPopularity, PvpMetaTalentPopularity].each do |model|
      model.where(pvp_sync_cycle_id: cycle.id).delete_all
    end
  end

  def purge_old_cycle_data(old_cycle_id)
    [PvpMetaItemPopularity, PvpMetaEnchantPopularity,
     PvpMetaGemPopularity, PvpMetaTalentPopularity].each do |model|
      model.where(pvp_sync_cycle_id: old_cycle_id).delete_all
    end
  end
```

**`for_meta` scope changes** (all 4 popularity models):

```ruby
scope :for_meta, ->(season:, bracket:, spec_id:) {
  live_cycle_id = season.live_pvp_sync_cycle_id
  base = includes(item: :translations)
    .where(pvp_season: season, bracket: bracket, spec_id: spec_id)
    .order(usage_pct: :desc)
  live_cycle_id ? base.where(pvp_sync_cycle_id: live_cycle_id) : base
}
```

The `live_cycle_id ? ... : base` fallback preserves current behavior when no live cycle exists (first run or migration period).

**Cache invalidation**: After promotion, bust the `pvp_meta/*` cache namespace so controllers serve fresh data from the newly promoted cycle.

### Testing

- `build_aggregations_job_spec.rb`:
  - All succeed → `live_pvp_sync_cycle_id` updated, old rows purged, new rows retained
  - Any fail → draft rows deleted, `live_pvp_sync_cycle_id` unchanged
- `pvp_meta_item_popularity_spec.rb`: `for_meta` returns only rows matching live cycle_id

---

## Full Cycle Flow (after all parts)

```
SyncCurrentSeasonLeaderboardsJob
  └─ creates PvpSyncCycle (syncing_leaderboards → syncing_characters)
  └─ SyncCharacterBatchJob × N
       └─ per character: ApplicationRecord.transaction { ProcessEquipment + ProcessSpec }
       └─ on failure: both timestamps null, sync_retry_count stays
       └─ when last batch done → RecoverFailedCharacterSyncsJob
  └─ RecoverFailedCharacterSyncsJob
       └─ finds null-timestamp entries (sync_retry_count < 3)
       └─ increments sync_retry_count, re-enqueues SyncCharacterBatchJob batches
       └─ exhausted entries (count=3) → Sentry warning
       └─ when no recoverable entries remain → BuildAggregationsJob
  └─ BuildAggregationsJob
       └─ runs 4 aggregations writing to new cycle_id (no delete)
       └─ all succeed → promote new cycle, purge old cycle data, bust cache
       └─ any fail   → delete draft rows, old live_cycle_id unchanged
       └─ failure    → Sentry capture, live data preserved
  └─ PvpSyncCycle status → completed / failed
```

---

## What Does NOT Change

- Blizzard API client error handling (retries already in place)
- `SyncBracketJob` retry logic
- `PvpSyncCycle` status machine
- Character meta sync (`SyncCharacterMetaBatchJob`) — separate pipeline
- Talent tree sync — covered by separate reliability plan

---

## Migrations Summary

1. `add_column :pvp_leaderboard_entries, :sync_retry_count, :integer, default: 0, null: false`
2. `add_reference :pvp_meta_item_popularity, :pvp_sync_cycle`
3. `add_reference :pvp_meta_enchant_popularity, :pvp_sync_cycle`
4. `add_reference :pvp_meta_gem_popularity, :pvp_sync_cycle`
5. `add_reference :pvp_meta_talent_popularity, :pvp_sync_cycle`
6. `add_reference :pvp_seasons, :live_pvp_sync_cycle, foreign_key: { to_table: :pvp_sync_cycles }`

All nullable — safe to deploy before code changes. Existing rows get null `pvp_sync_cycle_id` and fall back to current behavior.
