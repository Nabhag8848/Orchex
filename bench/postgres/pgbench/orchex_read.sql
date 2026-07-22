-- Point read of an active run (control-plane / worker status style).
\set nruns 60000
\set seq random(1, :nruns)

SELECT r.id, r.status, r.current_node_id, r.current_node_attempt, r.updated_at
FROM bench_run_map m
JOIN workflow_runs r ON r.id = m.run_id
WHERE m.seq = :seq;
