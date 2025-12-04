# Runbook — Worker Out Of Memory

---

## Purpose

This runbook explains how to triage, mitigate and recover from `Out-Of-Memory` (`OOM`) incidents affecting `ETL worker`
processes or other background workers in the StarForge platform. It covers immediate containment, diagnostic steps,
short-term mitigations, and long-term fixes to prevent future `OOMs`.

---

## Audience

- `SRE` / `Platform engineers`
- `Backend engineers` owning `ETL/worker` code
- `Incident commander` during worker incidents

---

## When to use

- Worker pods are `OOMKilled` or repeatedly restarting with `OOM` errors.
- Memory usage of workers continuously grows until the process is killed.
- High memory usage correlates with specific snapshots / jobs or a change in workload (backfills, deploy).

---

## Quick summary (first 5 minutes)

1. Acknowledge the alert and create an incident channel (e.g. `#incident-worker-oom-<ts>`).
2. Scale down or pause workers to stop repeated `OOM` events and prevent saturating the cluster.
3. Collect logs and pod diagnostics (`kubectl` logs, describe, events).
4. Identify whether `OOMs` are caused by specific snapshots (very large JSON), regressions in code, or a recent
   deployment.
5. If safe, start a single debug worker (with increased memory and debug logging) to reproduce locally or in staging.

---

## Triage checklist (immediate)

- [ ] Acknowledge alert and open incident channel.
- [ ] Identify affected pods / hosts:
    - `Kubernetes`: list pods with restarts and `OOMKilled` status.
    - Non-`K8s`: check system logs for `OOM` killer messages.
- [ ] Pause ingestion or reduce incoming load if needed.
- [ ] Scale down worker replicas to prevent further `OOM` kills.
- [ ] Capture diagnostics: pod logs, events, memory metrics, and failing job ids.

---

## Kubernetes quick commands

### List `ETL` worker pods and their status:

```bash
kubectl -n starforge get pods -l app=etl-worker -o wide
kubectl -n starforge describe pod <pod-name>
kubectl -n starforge logs <pod-name> --previous   # logs from previous container that OOMKilled
kubectl -n starforge logs <pod-name> --since=30m
kubectl -n starforge get events --sort-by='.lastTimestamp'
```

### Scale down quickly (emergency):

```bash
kubectl -n starforge scale deployment etl-worker --replicas=0
# or reduce to a safe number
kubectl -n starforge scale deployment etl-worker --replicas=1
```

---

## Diagnose OOM cause

1. Check pod events and container status: `kubectl describe pod ...` — look for `OOMKilled` in last state.
2. Inspect worker logs for stack traces, "JavaScript heap out of memory" (`Node`), or V8 `OOM` messages.
3. Correlate with metrics:
    - Pod memory usage from `Kubernetes` metrics / `prometheus`: `pod_memory_usage_bytes`
    - Worker restarts: `increase(kube_pod_container_status_restarts_total[5m])`
    - `ETL` metrics: `starforge_etl_processing_duration_seconds`, `starforge_etl_snapshots_processed_total`,
      `starforge_etl_snapshots_failed_total`
4. Identify job causing memory spike:
    - Look at logs to find `snapshot_id` being processed when crash occurred.
    - Query DB for recent processing attempts and large snapshots:
      ```sql
      SELECT id, size_bytes, created_at FROM hero_snapshots ORDER BY size_bytes DESC LIMIT 50;
      ```
5. Check recent deploys or config changes (`NODE_OPTIONS`, batch sizes) that may increase memory use.

---

## Containment & immediate mitigation

Do the least disruptive but effective actions first.

A) Stop the flood

- Pause ingestion (flip feature flag or return `503` on ingestion endpoints).
- Pause or remove heavy backfill jobs (see [./docs/OP_RUNBOOKS/BACKFILL.md](./BACKFILL.md)).

B) Scale down workers

- Scale replicas to `0`, or to `1` for debugging. This prevents repeated `OOM` kills.

C) Start a single debug worker

- Start one worker with increased memory and debug logging to reproduce the case:
    - In `Node.js`: `set NODE_OPTIONS="--max-old-space-size=4096"` (`MB`) or spawn a debug container with extended
      memory limit.
    - Consider enabling heap dumps on `OOM` (e.g. `--abort_on_uncaught_exception` and `heapdump` module) to capture heap
      snapshot.

D) Quarantine offending snapshots

- If a very large snapshot triggers `OOM`, quarantine it and process later on a high-memory worker:
  ```sql
  UPDATE hero_snapshots
  SET processing = false,
      error_count = COALESCE(error_count,0) + 1,
      last_error = to_jsonb('Quarantined: large snapshot causing OOM'::text)
  WHERE id = '<snapshot_id>';
  ```
- Optionally insert into a `quarantine_snapshots` table or push raw to `S3` for developer analysis.

E) Reduce per-worker load

- Reduce concurrency (worker threads / processes), batch sizes, and DB connection pool sizes for workers:
    - Example: `set WORKER_CONCURRENCY=1` and `PG_POOL_MAX=2` then restart workers.

---

## Diagnostics & reproduction (developer)

- Reproduce locally with the exact snapshot:
    1. Export raw JSON: `SELECT raw::text FROM hero_snapshots WHERE id = '<snapshot_id>';`
    2. Save to file and run the worker locally with debug flags and a heap profiler.
    3. Use streaming parser (stream-json) to exercise the memory behavior. Confirm if full `JSON` parse triggers the
       `OOM`.

- Capture heap snapshot:
    - Use Node's `--inspect` and heapdump library or `node --heap-prof` as appropriate.
    - Upload heap snapshot to secure storage for analysis with `Chrome DevTools` or heapprof tools.

---

## Short-term code/workflow mitigations

- Enforce streaming parsing for large arrays (troops, pets) instead of `JSON.parse` of the entire payload.
- Add per-snapshot size guard and skip/quarantine payloads larger than threshold (e.g., `5MB`) with admin alert.
- Reduce worker batch sizes for upserts (e.g., `100 -> 50`).
- Add backpressure: workers should back off on memory pressure and yield.
- Add memory limits at pod/container level with sensible requests/limits and autoscale based on `CPU` not memory alone.

---

## Node-specific tips

- Increase `V8` heap limit temporarily for debugging:
  ```bash
  NODE_OPTIONS="--max-old-space-size=4096"
  ```
- Use streaming `JSON` parsers (`stream-json`) to avoid building giant in-memory objects.
- Use `--trace-gc` or `--trace-gc-verbose` for `GC` diagnostics.
- Consider `--expose-gc` and perform explicit `GC` between large batches (last resort).

---

## Kubernetes resource tuning

- Ensure pod `resources.limits.memory` is set to a reasonable value and request matches expected usage.
- Enable `QoS` by providing requests and limits.
- Example deployment snippet:
  ```yaml
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
  ```
- Use `HPA` for `CPU` and consider custom metrics for queue length to scale workers safely.

---

## When to increase memory permanently

- Only after root cause analysis shows that workload legitimately requires more memory (e.g., payloads frequently `>2MB`
  and cannot be streamed).
- Prefer code/workflow changes over unbounded memory increases.
- If increasing memory, schedule for a controlled deployment and update pod limits/requests and cost estimates.

---

## Recovery & safe re-enable

1. Confirm root cause mitigations (streaming parse, reduced batch size, quarantined payloads, patched code).
2. Bring a small number of workers back online (`1–2`) and observe memory and error rates for `15–30 minutes`.
3. If stable, scale slowly to normal capacity.
4. Reintroduce quarantined snapshots using a high-memory worker or after applying a patch; reprocess only after
   validation.

---

## Post-incident actions (RCA)

- Produce a postmortem with timeline, root cause, detection & mitigation steps, and permanent fixes.
- Action items typically include:
    - Change `ETL` to streaming parsing.
    - Add snapshot size limits and quarantine workflow.
    - Improve memory testing in `CI`/perf tests (process large synthetic payloads).
    - Add `GC`/heap monitoring dashboards and alerts (e.g., `pod_memory_usage_bytes`,
      `kube_pod_container_status_restarts_total`).
    - Document and enforce worker resource limits and concurrency defaults.

---

## Monitoring & alerts to add/improve

- Alert when pod restarts increase: `increase(kube_pod_container_status_restarts_total[5m]) > 0`
- Alert when pod `memory > 85%` of limit: `pod_memory_usage_bytes / pod_memory_limit_bytes > 0.85`
- Track `starforge_etl_snapshots_failed_total{error_type="OOM"}` if you record error types.
- Instrument worker to emit `memory_usage_bytes` and `heap_used_bytes` if possible.

---

## Helpful SQL & housekeeping snippets

### Find largest snapshots:

```sql
SELECT id, size_bytes, created_at, source
FROM hero_snapshots
ORDER BY size_bytes DESC LIMIT 50;
```

### Mark snapshot as quarantined (example):

```sql
INSERT INTO snapshot_quarantine (id, snapshot_id, reason, created_at)
VALUES (gen_random_uuid(), '<snapshot_id>', 'OOM during processing', now());

UPDATE hero_snapshots
SET processing  = false,
    error_count = COALESCE(error_count, 0) + 1,
    last_error  = to_jsonb('Quarantined due to OOM'::text)
WHERE id = '<snapshot_id>';
```

### Re-enqueue a quarantined snapshot to special high-memory worker later:

```sql
INSERT INTO queue_jobs (id, type, payload, priority, status, created_at, updated_at)
VALUES (gen_random_uuid(), 'process_snapshot_highmem', jsonb_build_object('snapshot_id', '<snapshot_id>'), 10,
        'pending', now(), now());
```

---

## Example logs to gather for incident artifacts

- `kubectl -n starforge logs <pod> --previous`
- `kubectl -n starforge describe pod <pod>`
- Node process stderr / stack traces
- Heap profile files if captured
- `ps aux` / memory maps on host if not containerized

---

## Appendix: tips for developers to avoid OOMs

- Prefer streaming parsers for large `JSON` fields.
- Avoid building full in-memory representations of very large arrays.
- Upsert in small batches (configurable).
- Use connection pooling conservatively (small per-process pools).
- Add defensive guards: max snapshot size, per-job memory guardrails, and watchdogs that capture heap dumps.
- Add unit and integration tests with large synthetic snapshots to exercise memory usage.

---
