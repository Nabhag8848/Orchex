# Orchex OLTP bench image: Postgres + pgbench + init schema/seed.
# Uses locally cached pgvector/pg17 (Postgres 17) to avoid a fresh Hub pull.
FROM pgvector/pgvector:pg17

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends postgresql-contrib python3 \
  && rm -rf /var/lib/apt/lists/*

# Schema + seed run on first boot via official entrypoint.
COPY init/ /docker-entrypoint-initdb.d/

# Bench scripts + runner (executed via docker compose exec).
COPY pgbench/ /bench/pgbench/
COPY scripts/run_all_benchmarks.sh /bench/run_all_benchmarks.sh
RUN chmod +x /bench/run_all_benchmarks.sh /bench/pgbench/*.sh

WORKDIR /bench
USER postgres