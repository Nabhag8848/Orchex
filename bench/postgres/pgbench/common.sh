#!/usr/bin/env bash
# Helper wrappers around pgbench for Orchex scripts.
set -euo pipefail

PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-orchex}"
PGDATABASE="${PGDATABASE:-orchex}"
export PGPASSWORD="${PGPASSWORD:-orchex}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_pgbench() {
  local label="$1"
  shift
  echo
  echo "===== ${label} ====="
  echo "cmd: pgbench $*"
  pgbench -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" "$@"
}
