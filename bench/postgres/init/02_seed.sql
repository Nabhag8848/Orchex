-- Seed one published 10-node workflow + 60k concurrent runs for pgbench.
-- Assumptions: 10 hops/run; start targets 10 TPS steady / 100 TPS peak
-- => hop write targets ~100 TPS steady / ~1000 TPS peak.

TRUNCATE bench_node_ring, bench_run_map, run_node_jobs_outbox, workflow_runs,
  workflow_edges, nodes, workflow_versions, workflows, node_types CASCADE;

INSERT INTO node_types (id, type, category, display_name, min_in_degree, max_in_degree, min_out_degree, max_out_degree)
VALUES
  ('01000000-0000-4000-8000-000000000001', 'start', 'trigger', 'Start', 0, 0, 1, 1),
  ('01000000-0000-4000-8000-000000000002', 'function', 'logic', 'Function', 1, 1, 1, 1),
  ('01000000-0000-4000-8000-000000000003', 'response', 'terminal', 'Response', 1, 1, 0, 0);

INSERT INTO workflows (id, name, description, status)
VALUES (
  '11111111-1111-4111-8111-111111111111',
  'bench-workflow',
  '10-hop bench workflow',
  'published'
);

INSERT INTO workflow_versions (id, workflow_id, version, published_at)
VALUES (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  1,
  now()
);

UPDATE workflows
SET
  latest_version_id = '22222222-2222-4222-8222-222222222222',
  latest_published_version_id = '22222222-2222-4222-8222-222222222222',
  last_published_at = now(),
  status = 'published'
WHERE id = '11111111-1111-4111-8111-111111111111';

INSERT INTO nodes (id, workflow_version_id, node_type_id, name, position_x, position_y)
VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa0', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000001', 'n0_start', 0, 0),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000002', 'n1', 1, 0),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000002', 'n2', 2, 0),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000002', 'n3', 3, 0),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000002', 'n4', 4, 0),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000002', 'n5', 5, 0),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000002', 'n6', 6, 0),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000002', 'n7', 7, 0),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa8', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000002', 'n8', 8, 0),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa9', '22222222-2222-4222-8222-222222222222', '01000000-0000-4000-8000-000000000003', 'n9_response', 9, 0);

INSERT INTO workflow_edges (id, workflow_version_id, from_node_id, to_node_id, label)
SELECT
  gen_random_uuid(),
  '22222222-2222-4222-8222-222222222222',
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa' || i)::uuid,
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa' || (i + 1))::uuid,
  'default'
FROM generate_series(0, 8) AS i;

INSERT INTO bench_node_ring (hop, node_id)
SELECT i, ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa' || i)::uuid
FROM generate_series(0, 9) AS i;

INSERT INTO workflow_runs (
  id, workflow_id, workflow_version_id, status, trigger_type,
  current_node_id, current_node_attempt, started_at
)
SELECT
  ('bbbbbbbb-bbbb-4bbb-8bbb-' || lpad(to_hex(g), 12, '0'))::uuid,
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'running',
  'manual',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa0',
  1,
  now()
FROM generate_series(1, 60000) AS g;

INSERT INTO bench_run_map (seq, run_id)
SELECT
  g,
  ('bbbbbbbb-bbbb-4bbb-8bbb-' || lpad(to_hex(g), 12, '0'))::uuid
FROM generate_series(1, 60000) AS g;

ANALYZE;
