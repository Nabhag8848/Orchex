-- Orchex hot path: guarded checkpoint advance + outbox insert + relay delete.
-- Each transaction advances one hop on a random active run (10-node ring).

\set nruns 60000
\set seq random(1, :nruns)

BEGIN;

WITH advanced AS (
  UPDATE workflow_runs AS r
  SET
    current_node_id = n_next.node_id,
    current_node_attempt = 1,
    updated_at = now()
  FROM bench_run_map AS m,
       bench_node_ring AS n_cur,
       bench_node_ring AS n_next
  WHERE m.seq = :seq
    AND r.id = m.run_id
    AND n_cur.node_id = r.current_node_id
    AND n_next.hop = ((n_cur.hop + 1) % 10)
    AND r.current_node_attempt = 1
    AND r.status = 'running'
  RETURNING r.id AS run_id, r.workflow_version_id, n_next.node_id AS next_node_id
)
INSERT INTO run_node_jobs_outbox (run_id, workflow_version_id, node_id, attempt)
SELECT run_id, workflow_version_id, next_node_id, 1
FROM advanced;

DELETE FROM run_node_jobs_outbox
WHERE id IN (
  SELECT id
  FROM run_node_jobs_outbox
  WHERE available_at IS NULL OR available_at <= now()
  ORDER BY created_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1
);

COMMIT;
