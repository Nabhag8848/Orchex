#!/usr/bin/env bash
# Run Orchex Postgres benchmarks and write a markdown report.
set -euo pipefail

export PGHOST="${PGHOST:-localhost}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-orchex}"
export PGDATABASE="${PGDATABASE:-orchex}"
export PGPASSWORD="${PGPASSWORD:-orchex}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}"
PGBENCH_DIR="${ROOT_DIR}/pgbench"
OUT_DIR="${ROOT_DIR}/results"
mkdir -p "${OUT_DIR}"

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
HOST_INFO_FILE="${OUT_DIR}/_host_${TS}.txt"
RAW_DIR="${OUT_DIR}/raw_${TS}"
mkdir -p "${RAW_DIR}"
REPORT="${OUT_DIR}/BENCHMARK_RESULTS.md"

echo "Waiting for Postgres..."
for i in $(seq 1 60); do
  if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE"

{
  echo "timestamp_utc: ${TS}"
  echo "pghost: ${PGHOST}"
  uname -a || true
  nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || true
  free -h 2>/dev/null || true
  cat /proc/meminfo 2>/dev/null | head -5 || true
  psql -c "SELECT version();"
  psql -c "SHOW max_connections;"
  psql -c "SHOW shared_buffers;"
  psql -c "SHOW work_mem;"
  psql -c "SELECT
    (SELECT count(*) FROM workflow_runs) AS runs,
    (SELECT count(*) FROM run_node_jobs_outbox) AS outbox,
    (SELECT count(*) FROM nodes) AS nodes;"
} > "${HOST_INFO_FILE}" 2>&1

run_one() {
  local name="$1"
  shift
  local out="${RAW_DIR}/${name}.txt"
  echo ">> Running ${name}"
  # shellcheck disable=SC2068
  set +e
  pgbench -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" $@ >"${out}" 2>&1
  local rc=$?
  set -e
  echo "exit_code=${rc}" >>"${out}"
  echo ">> Done ${name} (exit ${rc})"
}

# 1) Built-in pgbench init + short ceiling (reference only; separate scale factor tables).
run_one "01_builtin_init" -i -s 50
run_one "02_builtin_max_c8_j4_T30" -c 8 -j 4 -T 30 -P 10

# Drop pgbench tables noise? Keep them; Orchex tables unaffected.

# 2) Orchex hop write path — find max throughput
run_one "03_orchex_hop_max_c4_j2_T30" -c 4 -j 2 -T 30 -P 10 -f "${PGBENCH_DIR}/orchex_hop.sql" -n
run_one "04_orchex_hop_max_c8_j4_T30" -c 8 -j 4 -T 30 -P 10 -f "${PGBENCH_DIR}/orchex_hop.sql" -n
run_one "05_orchex_hop_max_c16_j8_T30" -c 16 -j 8 -T 30 -P 10 -f "${PGBENCH_DIR}/orchex_hop.sql" -n

# 3) Sustained target rates (10 hops assumption)
# Steady hop rate ~100 TPS; peak ~1000 TPS
run_one "06_orchex_hop_rate100_c8_j4_T30" -c 8 -j 4 -T 30 -R 100 -f "${PGBENCH_DIR}/orchex_hop.sql" -n
run_one "07_orchex_hop_rate1000_c16_j8_T45" -c 16 -j 8 -T 45 -R 1000 -f "${PGBENCH_DIR}/orchex_hop.sql" -n

# 4) Reads
run_one "08_orchex_read_max_c16_j8_T30" -c 16 -j 8 -T 30 -P 10 -f "${PGBENCH_DIR}/orchex_read.sql" -n
run_one "09_orchex_read_rate500_c8_j4_T30" -c 8 -j 4 -T 30 -R 500 -f "${PGBENCH_DIR}/orchex_read.sql" -n

# Capture ending DB stats
psql -c "SELECT
  (SELECT count(*) FROM workflow_runs) AS runs,
  (SELECT count(*) FROM run_node_jobs_outbox) AS outbox_rows,
  (SELECT pg_size_pretty(pg_total_relation_size('workflow_runs'))) AS runs_size,
  (SELECT pg_size_pretty(pg_total_relation_size('run_node_jobs_outbox'))) AS outbox_size;" \
  > "${RAW_DIR}/10_final_counts.txt" 2>&1

# Build markdown report
python3 - <<'PY' "${REPORT}" "${HOST_INFO_FILE}" "${RAW_DIR}" "${TS}"
import sys, pathlib, re

report, host_file, raw_dir, ts = sys.argv[1:5]
raw = pathlib.Path(raw_dir)
host = pathlib.Path(host_file).read_text(errors="replace")

def parse_pgbench(text: str):
    def m(pat, cast=float):
        x = re.search(pat, text)
        return cast(x.group(1)) if x else None
    return {
        "scale": m(r"scaling factor: (\d+)", int),
        "clients": m(r"number of clients: (\d+)", int),
        "threads": m(r"number of threads: (\d+)", int),
        "duration": m(r"duration: (\d+)", int),
        "tps_excl": m(r"tps = ([0-9.]+) \(without initial connection time\)") or m(r"tps = ([0-9.]+) \(excluding connections establishing\)"),
        "tps_incl": m(r"tps = ([0-9.]+) \(including connections establishing\)"),
        "latency_avg": m(r"latency average = ([0-9.]+)"),
        "latency_std": m(r"latency stddev = ([0-9.]+)"),
        "failed": m(r"number of failed transactions: (\d+)", int) or 0,
    }

rows = []
for p in sorted(raw.glob("*.txt")):
    text = p.read_text(errors="replace")
    meta = parse_pgbench(text)
    # rate from filename hints
    rate_hint = None
    rm = re.search(r"rate(\d+)", p.stem)
    if rm:
        rate_hint = int(rm.group(1))
    rows.append((p.stem, meta, text, rate_hint))

lines = []
lines.append("# Orchex Postgres pgbench results")
lines.append("")
lines.append(f"- Generated (UTC): `{ts}`")
lines.append("- Branch target: local Docker Postgres 17 (not RDS/Aurora instance proof)")
lines.append("- Workload assumption: **10 hops per workflow**")
lines.append("- Start targets: **10 TPS steady / 100 TPS peak** → hop write targets **~100 / ~1000 TPS**")
lines.append("- Seed: **60,000** concurrent `workflow_runs` on one 10-node published version")
lines.append("")
lines.append("## Important limits of this test")
lines.append("")
lines.append("1. This proves **Postgres + this schema + this SQL mix** on a **capped Docker container**, not a specific AWS instance class.")
lines.append("2. Docker on a laptop shares CPU/disk with other apps; numbers will differ on RDS.")
lines.append("3. Custom script models checkpoint `UPDATE` + outbox `INSERT` + one `SKIP LOCKED` delete (relay).")
lines.append("4. Built-in pgbench (`pgbench_accounts` etc.) is only a **reference ceiling**, not Orchex.")
lines.append("")
lines.append("## Environment snapshot")
lines.append("")
lines.append("```")
lines.append(host.strip())
lines.append("```")
lines.append("")
lines.append("## Summary table")
lines.append("")
lines.append("| Run | Clients | Threads | Duration (s) | Target rate | TPS (excl setup) | Avg latency (ms) | Failed txns |")
lines.append("|---|---:|---:|---:|---:|---:|---:|---:|")
for name, meta, text, rate_hint in rows:
    if meta["tps_excl"] is None and "builtin_init" in name:
        lines.append(f"| `{name}` | init | — | — | — | — | — | — |")
        continue
    lines.append(
        "| `{name}` | {c} | {t} | {d} | {r} | {tps} | {lat} | {f} |".format(
            name=name,
            c=meta["clients"] if meta["clients"] is not None else "—",
            t=meta["threads"] if meta["threads"] is not None else "—",
            d=meta["duration"] if meta["duration"] is not None else "—",
            r=rate_hint if rate_hint is not None else "max",
            tps=f"{meta['tps_excl']:.2f}" if meta["tps_excl"] is not None else "—",
            lat=f"{meta['latency_avg']:.3f}" if meta["latency_avg"] is not None else "—",
            f=meta["failed"] if meta["failed"] is not None else "—",
        )
    )

lines.append("")
lines.append("## Pass / fail vs Orchex targets")
lines.append("")
lines.append("| Target | Meaning | How to read results |")
lines.append("|---|---|---|")
lines.append("| Steady hops ~100 TPS | 10 starts/s × 10 hops | Rate-limited run `06_*rate100*` should show ~100 TPS, low failures |")
lines.append("| Peak hops ~1000 TPS | 100 starts/s × 10 hops | Rate-limited run `07_*rate1000*` should hold ~1000 TPS, low failures |")
lines.append("| Headroom | Max hop TPS | Max runs `03`/`04`/`05` should be **comfortably above 1000** if this box is enough |")
lines.append("")

# Auto verdict from parsed numbers
hop_max = [meta["tps_excl"] for name, meta, _, _ in rows if "orchex_hop_max" in name and meta["tps_excl"]]
rate1000 = next((meta for name, meta, _, _ in rows if "rate1000" in name), None)
rate100 = next((meta for name, meta, _, _ in rows if "rate100_" in name or name.endswith("rate100_c8_j4_T30")), None)

lines.append("### Auto verdict (heuristic)")
lines.append("")
if hop_max:
    lines.append(f"- Max observed Orchex-hop TPS (best of max runs): **{max(hop_max):.2f}**")
else:
    lines.append("- Max Orchex-hop TPS: not parsed")
if rate100 and rate100["tps_excl"] is not None:
    ok = rate100["tps_excl"] >= 95 and (rate100["failed"] or 0) == 0
    lines.append(f"- Steady 100 TPS run: **{'PASS' if ok else 'CHECK'}** (measured {rate100['tps_excl']:.2f} TPS, failed={rate100['failed']})")
if rate1000 and rate1000["tps_excl"] is not None:
    ok = rate1000["tps_excl"] >= 950 and (rate1000["failed"] or 0) == 0
    lines.append(f"- Peak 1000 TPS run: **{'PASS' if ok else 'CHECK'}** (measured {rate1000['tps_excl']:.2f} TPS, failed={rate1000['failed']})")
lines.append("")
lines.append("## Raw pgbench output")
lines.append("")
for name, meta, text, rate_hint in rows:
    lines.append(f"### `{name}`")
    lines.append("")
    lines.append("```")
    lines.append(text.strip())
    lines.append("```")
    lines.append("")

pathlib.Path(report).write_text("\n".join(lines) + "\n")
print(f"Wrote {report}")
PY

echo "Report: ${REPORT}"
