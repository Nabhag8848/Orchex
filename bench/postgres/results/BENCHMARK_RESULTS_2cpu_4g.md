# Orchex Postgres pgbench results

- Generated (UTC): `2026-07-22T11:01:27Z`
- Branch: `bench/postgres-oltp-pgbench`
- Engine: **PostgreSQL 17.10** in Docker (`pgvector/pgvector:pg17` base)
- Container caps: **2 CPUs**, **4 GB RAM**, `shared_buffers=128MB` (Postgres defaults)
- **Not** an RDS/Aurora instance-size proof — laptop Docker with resource caps

## Workload assumptions

| Assumption | Value |
|---|---|
| Hops per workflow | **10** |
| New run starts (steady / peak) | **10 / 100 TPS** |
| Implied hop writes (steady / peak) | **~100 / ~1000 TPS** |
| Seeded concurrent runs | **60,000** |
| Hot transaction | checkpoint `UPDATE` + outbox `INSERT` + one relay `DELETE … SKIP LOCKED` |

## Plain-language verdict

**Yes — on this boxed Postgres, the Orchex write mix held the targets with zero failed transactions.**

| Target | Result | Verdict |
|---|---|---|
| Steady ~100 hop TPS | **101.2 TPS**, 0 failures, ~6.1 ms avg latency | **PASS** |
| Peak ~1000 hop TPS | **1000.8 TPS**, 0 failures, ~6.4 ms avg latency | **PASS** |
| Headroom (max push) | Best max run **~4706 TPS** (4 clients) | **Comfortable headroom** above 1000 |

Caveats:

1. This is Docker on a Mac, not AWS RDS. Real RDS numbers will differ (disk, network, neighbors).
2. Pushing **too many clients** (16) made hop TPS **worse** (~700) because many workers fought over the same outbox delete queue — more connections ≠ always faster.
3. Default `shared_buffers=128MB` is small vs a tuned RDS; a managed instance would usually be configured higher.

## Summary table

| Run | What it means | Clients | Threads | Duration | Target rate | TPS | Avg latency | Failed |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `02_builtin_max` | Generic pgbench (reference only) | 8 | 4 | 30s | max | **3437** | 2.31 ms | 0 |
| `03_orchex_hop_max` | Orchex hop, find ceiling | 4 | 2 | 30s | max | **4706** | 0.85 ms | 0 |
| `04_orchex_hop_max` | Orchex hop, more clients | 8 | 4 | 30s | max | **2551** | 3.13 ms | 0 |
| `05_orchex_hop_max` | Orchex hop, even more clients | 16 | 8 | 30s | max | **700** | 22.9 ms | 0 |
| `06_orchex_hop_rate100` | Steady target | 8 | 4 | 30s | 100 | **101** | 6.14 ms | 0 |
| `07_orchex_hop_rate1000` | Peak target | 16 | 8 | 45s | 1000 | **1001** | 6.42 ms | 0 |
| `08_orchex_read_max` | Point-read run by id | 16 | 8 | 30s | max | **15821** | 1.01 ms | 0 |
| `09_orchex_read_rate500` | Controlled reads | 8 | 4 | 30s | 500 | *(rate-limited; see raw)* | 2.30 ms | 0 |

## Environment snapshot

```
PostgreSQL 17.10 (Debian) aarch64
max_connections = 100
shared_buffers  = 128MB
work_mem        = 4MB
Container approx host view: ~8 GB MemTotal visible in VM, 8 nproc
Seed at start: 60000 runs, 0 outbox, 10 nodes
After bench:   60000 runs, 0 outbox rows, runs_size=14MB, outbox_size=14MB
```

## How to read “TPS” here

- **1 TPS** in the Orchex hop script = **one full hop transaction** (update checkpoint + insert outbox + try delete one outbox row).
- Steady Orchex need ≈ `10 starts/s × 10 hops = 100 hop TPS`.
- Peak Orchex need ≈ `100 starts/s × 10 hops = 1000 hop TPS`.

## Interesting finding (keep for design)

At 4 clients, hop TPS peaked (~4706). At 16 clients, it dropped (~700) while latency jumped. Likely cause: many concurrent `DELETE … ORDER BY created_at FOR UPDATE SKIP LOCKED` on the outbox. For production relay, keep relay concurrency modest (or move to CDC) — don’t assume “more pollers = more throughput.”

## Raw outputs

Full pgbench logs are under:

`bench/postgres/results/raw_2026-07-22T11:01:27Z/`

### `03_orchex_hop_max_c4_j2_T30` (best hop ceiling)

```
tps = 4706.146682 (without initial connection time)
number of transactions actually processed: 141176
number of failed transactions: 0
latency average = 0.849 ms
```

### `06_orchex_hop_rate100_c8_j4_T30` (steady)

```
tps = 101.173796 (without initial connection time)
number of failed transactions: 0
```

### `07_orchex_hop_rate1000_c16_j8_T45` (peak)

```
tps = 1000.825102 (without initial connection time)
number of failed transactions: 0
rate limit schedule lag: avg 4.357 (max 233.944) ms
```

## Reproduce

```bash
cd bench/postgres
docker compose down -v
docker compose up -d --build
docker compose exec -u root postgres bash -lc \
  'export PGHOST=localhost PGUSER=orchex PGPASSWORD=orchex PGDATABASE=orchex; /bench/run_all_benchmarks.sh'
```

Report path: `bench/postgres/results/BENCHMARK_RESULTS.md`
