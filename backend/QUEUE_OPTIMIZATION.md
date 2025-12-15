# Queue Optimization Guide

This document explains the queue configuration optimizations for 2-core CPU environments.

## Overview

The queue configuration has been optimized for efficient operation on 2-core CPU instances (e.g., cheapest tier cloud VMs). The key principle is to **avoid thread oversubscription** and **reduce context switching**.

## Key Changes

### Before Optimization
- Total threads: 14 (3 sync + 8 processing + 3 default)
- High thread contention on 2 CPU cores
- Excessive context switching overhead
- Aggressive polling intervals (0.05-0.1s)

### After Optimization
- Total threads: 8 (2 sync + 4 processing + 2 default)
- Threads ≈ 4x CPU cores (optimal for I/O-bound workloads)
- Reduced polling overhead (0.5s)
- Smaller batch sizes (100) for lower memory pressure

## Environment Variables

### Thread Configuration

```bash
# Sync workers (I/O-bound: API calls to Blizzard)
PVP_SYNC_THREADS=2          # Default: 2 (was 3)

# Processing workers (CPU-bound: parsing equipment JSON)
PVP_PROCESSING_THREADS=4    # Default: 4 (was 8)

# Default queue workers
DEFAULT_THREADS=2           # Default: 2 (was 3)
```

### Polling Configuration

```bash
# Sync worker polling interval
SYNC_POLLING_INTERVAL=0.5   # Default: 0.5s (was 0.1s)

# Processing worker polling interval
PROCESSING_POLLING_INTERVAL=0.5  # Default: 0.5s (was 0.05s)
```

### Batch Configuration

```bash
# Dispatcher batch size
BATCH_SIZE=100              # Default: 100 (was 500)
```

## Rationale

### Thread Count Optimization

**I/O-bound jobs (sync)**: Use 2 threads
- Character sync jobs spend most time waiting on Blizzard API responses
- More threads = better API utilization
- 2 threads on 2 cores allows some overlap during I/O waits

**CPU-bound jobs (processing)**: Use 4 threads
- Equipment parsing is CPU-intensive
- Too many threads = context switching overhead
- 4 threads = 2x CPU cores (good balance for mixed workload)

### Polling Interval Optimization

- Increased from 0.05-0.1s to 0.5s
- Reduces CPU usage by ~80% for polling overhead
- Minimal impact on job latency (jobs still start within 0.5s)
- Significant battery/power savings on VMs

### Batch Size Optimization

- Reduced from 500 to 100
- Lower memory pressure per dispatcher cycle
- Faster job distribution to workers
- Better responsiveness for high-priority jobs

## Performance Impact

### Expected Improvements

1. **CPU Efficiency**: ~50% reduction in context switching overhead
2. **Throughput**: Maintained or improved due to better core utilization
3. **Memory**: ~80% reduction in peak memory usage per batch
4. **Latency**: Slight increase (~0.4s avg) but negligible for background jobs
5. **Cost**: Lower CPU usage = potential cost savings on cloud VMs

### Scalability

To scale up on more powerful instances:

```bash
# 4-core instance
PVP_SYNC_THREADS=4
PVP_PROCESSING_THREADS=8

# 8-core instance
PVP_SYNC_THREADS=8
PVP_PROCESSING_THREADS=16
```

Rule of thumb: 
- Sync threads ≈ CPU cores
- Processing threads ≈ 2x CPU cores

## Monitoring

Monitor these metrics to tune further:

1. **Queue depth**: Jobs waiting in queue
2. **Job latency**: Time from enqueue to start
3. **CPU utilization**: Should be 70-80% under load
4. **Context switches**: Check with `vmstat` or CloudWatch

## Reverting Changes

To revert to previous configuration:

```bash
PVP_SYNC_THREADS=3
PVP_PROCESSING_THREADS=8
DEFAULT_THREADS=3
BATCH_SIZE=500
SYNC_POLLING_INTERVAL=0.1
PROCESSING_POLLING_INTERVAL=0.05
```

## Further Reading

- [SolidQueue Documentation](https://github.com/rails/solid_queue)
- [Thread vs Process Concurrency](https://en.wikipedia.org/wiki/Thread_(computing))
- [Context Switching Overhead](https://en.wikipedia.org/wiki/Context_switch)
