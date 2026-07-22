# Orchex Postgres bench — 1 CPU / 2 GB

- Generated (UTC): `2026-07-22T11:20:42Z` (+ peak retries)
- Engine: PostgreSQL 17.10 in Docker
- Hard limits verified: `NanoCPUs=1e9` (1 CPU), `Memory=2GiB`, `ShmSize=128MB`
- Same workload as before: **10 hops**, targets **~100 / ~1000** hop TPS, **60k** seeded runs

Compare with previous run: `BENCHMARK_RESULTS_2cpu_4g.md`

## Verdict

| Target | 1 CPU / 2 GB | Notes |
|---|---|---|
| Steady ~100 hop TPS | **PASS** (100.8 TPS, 0 failed) | Fine |
| Peak ~1000 hop TPS | **PASS only with few clients** (~991 TPS @ 4 clients) | **FAIL** at 8–16 clients (lag explodes) |
| Max hop ceiling | **~2182 TPS** @ 4 clients | Lower than 2c/4g (~4706) but still above 1000 |
| Memory used under load | **~171 MiB / 2 GiB** | RAM was not the bottleneck |

**Bottom line:** 1 vCPU / 2 GB *can* hold Orchex peak **if** worker/relay concurrency stays modest (~4 DB clients for this mix). It does **not** tolerate the “open many connections” style that worked on 2 CPU / 4 GB.

## Side-by-side

| Run | 2 CPU / 4 GB | 1 CPU / 2 GB |
|---|---:|---:|
| Builtin pgbench max (c8) | 3437 TPS | 1633 TPS |
| Orchex hop max c4 | **4706** TPS | **2182** TPS |
| Orchex hop max c8 | 2551 TPS | 991 TPS |
| Orchex hop max c16 | 700 TPS | 394 TPS |
| Rate 100 (c8) | **101** TPS | **101** TPS |
| Rate 1000 (c16) | **1001** TPS | **504** TPS (FAIL) |
| Rate 1000 (c4) retry | — | **991** TPS (PASS-ish) |
| Rate 1000 (c8) retry | — | **392** TPS (FAIL) |
| Read max (c16) | 15821 TPS | 5572 TPS |

## Suite results (1c / 2g)

| Run | Clients | TPS | Avg latency | Failed |
|---|---:|---:|---:|---:|
| `02_builtin_max` | 8 | 1633 | 4.90 ms | 0 |
| `03_orchex_hop_max` | 4 | **2182** | 1.83 ms | 0 |
| `04_orchex_hop_max` | 8 | 991 | 8.07 ms | 0 |
| `05_orchex_hop_max` | 16 | 394 | 40.4 ms | 0 |
| `06_orchex_hop_rate100` | 8 | **101** | 5.69 ms | 0 |
| `07_orchex_hop_rate1000` | 16 | **504** | 6481 ms | 0 |
| `08_orchex_read_max` | 16 | 5572 | 2.84 ms | 0 |

### Peak retries (same box)

| Run | Clients | TPS | Avg latency | Schedule lag max | Verdict |
|---|---:|---:|---:|---:|---|
| rate 1000 | 4 | **991** | 3.5 ms | 162 ms | **PASS** (within ~1%) |
| rate 1000 | 8 | 392 | 11069 ms | 27.7 s | **FAIL** |

## Recommendation

- **Steady traffic (10 starts/s):** 1 vCPU / 2 GB is enough.
- **Peak traffic (100 starts/s):** 1 vCPU / 2 GB is **tight but workable** only with careful connection limits; prefer **2 vCPU / 4 GB** for safer headroom and messier client counts.
- RAM at 2 GB was plenty for this dataset; CPU + lock contention on outbox deletes were the limiter.
