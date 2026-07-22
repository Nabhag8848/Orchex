# Postgres OLTP bench (Docker + pgbench)

Local harness to load-test the Orchex schema with an Orchex-shaped write mix.

## Assumptions

- **10 hops** per workflow
- Starts: **10 TPS** steady / **100 TPS** peak
- Hop writes: **~100 TPS** steady / **~1000 TPS** peak
- Seed: **60k** concurrent runs

## Quick start

```bash
cd bench/postgres
docker compose down -v
docker compose up -d --build
# wait until healthy, then:
docker compose exec postgres /bench/run_all_benchmarks.sh
```

Report: `bench/postgres/results/BENCHMARK_RESULTS.md`

## Note

This does **not** prove a specific RDS/Aurora instance size. It proves Postgres can run this SQL mix at a given TPS on a **2 CPU / 4GB Docker cap**.
