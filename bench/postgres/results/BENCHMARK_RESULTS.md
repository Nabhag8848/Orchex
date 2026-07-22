# Orchex Postgres pgbench results (latest run)

Latest limits: **1 CPU / 2 GB** — see full write-up:

- [BENCHMARK_RESULTS_1cpu_2g.md](./BENCHMARK_RESULTS_1cpu_2g.md) ← **this run**
- [BENCHMARK_RESULTS_2cpu_4g.md](./BENCHMARK_RESULTS_2cpu_4g.md) ← previous 2 CPU / 4 GB run

## Quick answer

| Box | Steady 100 hop TPS | Peak 1000 hop TPS |
|---|---|---|
| 2 CPU / 4 GB | PASS | PASS (even with 16 clients) |
| 1 CPU / 2 GB | PASS | PASS only with ~4 clients; FAIL with 8–16 |

Prefer **2 vCPU / 4 GB** for production peak comfort. **1 / 2** works for steady and can scrape peak if concurrency is kept low.
