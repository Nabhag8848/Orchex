-- Orchex OLTP schema (from schema.dbml) for local pgbench.
-- Applied once on first Postgres container boot.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE node_category AS ENUM ('trigger', 'logic', 'action', 'terminal');
CREATE TYPE workflow_status AS ENUM ('draft', 'published', 'archived');
CREATE TYPE edge_label AS ENUM ('default', 'true', 'false');
CREATE TYPE trigger_type AS ENUM ('manual', 'webhook', 'scheduler');
CREATE TYPE workflow_run_status AS ENUM (
  'pending', 'running', 'paused', 'failed', 'completed', 'cancelled'
);

CREATE TABLE node_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL UNIQUE,
  category node_category NOT NULL,
  display_name text NOT NULL,
  min_in_degree int NOT NULL,
  max_in_degree int NOT NULL,
  min_out_degree int NOT NULL,
  max_out_degree int NOT NULL,
  config_schema jsonb NOT NULL DEFAULT '{}',
  input_schema jsonb NOT NULL DEFAULT '{}',
  output_schema jsonb NOT NULL DEFAULT '{}',
  error_schema jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE workflows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  status workflow_status NOT NULL DEFAULT 'draft',
  latest_published_version_id uuid,
  latest_version_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_published_at timestamptz
);

CREATE TABLE workflow_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES workflows(id),
  version int NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_updated_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  CONSTRAINT uq_workflow_versions_workflow_version UNIQUE (workflow_id, version)
);

CREATE UNIQUE INDEX uq_workflow_versions_one_draft
  ON workflow_versions (workflow_id)
  WHERE published_at IS NULL;

-- Circular FKs: add after both tables exist (no DEFERRABLE needed for seed order).
ALTER TABLE workflows
  ADD CONSTRAINT workflows_latest_version_id_fkey
  FOREIGN KEY (latest_version_id) REFERENCES workflow_versions(id);

ALTER TABLE workflows
  ADD CONSTRAINT workflows_latest_published_version_id_fkey
  FOREIGN KEY (latest_published_version_id) REFERENCES workflow_versions(id);

CREATE TABLE nodes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  workflow_version_id uuid NOT NULL REFERENCES workflow_versions(id),
  node_type_id uuid NOT NULL REFERENCES node_types(id),
  name text NOT NULL,
  config jsonb NOT NULL DEFAULT '{}',
  position_x double precision,
  position_y double precision,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workflow_version_id, id),
  CONSTRAINT uq_nodes_version_name UNIQUE (workflow_version_id, name)
);

CREATE TABLE workflow_edges (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  workflow_version_id uuid NOT NULL REFERENCES workflow_versions(id),
  from_node_id uuid NOT NULL,
  to_node_id uuid NOT NULL,
  label edge_label NOT NULL DEFAULT 'default',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workflow_version_id, id),
  CONSTRAINT uq_workflow_edges_source_label UNIQUE (workflow_version_id, from_node_id, label),
  CONSTRAINT workflow_edges_from_fkey
    FOREIGN KEY (workflow_version_id, from_node_id)
    REFERENCES nodes (workflow_version_id, id),
  CONSTRAINT workflow_edges_to_fkey
    FOREIGN KEY (workflow_version_id, to_node_id)
    REFERENCES nodes (workflow_version_id, id)
);

CREATE TABLE workflow_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id uuid NOT NULL REFERENCES workflows(id),
  workflow_version_id uuid NOT NULL REFERENCES workflow_versions(id),
  status workflow_run_status NOT NULL DEFAULT 'pending',
  trigger_type trigger_type NOT NULL DEFAULT 'manual',
  current_node_id uuid NOT NULL,
  current_node_attempt int NOT NULL DEFAULT 1,
  error jsonb,
  started_at timestamptz,
  paused_at timestamptz,
  cancelled_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_workflow_runs_id_version UNIQUE (id, workflow_version_id),
  CONSTRAINT workflow_runs_checkpoint_fkey
    FOREIGN KEY (workflow_version_id, current_node_id)
    REFERENCES nodes (workflow_version_id, id)
);

CREATE TABLE run_node_jobs_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL,
  workflow_version_id uuid NOT NULL,
  node_id uuid NOT NULL,
  attempt int NOT NULL DEFAULT 1,
  available_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT run_node_jobs_outbox_run_fkey
    FOREIGN KEY (run_id, workflow_version_id)
    REFERENCES workflow_runs (id, workflow_version_id),
  CONSTRAINT run_node_jobs_outbox_node_fkey
    FOREIGN KEY (workflow_version_id, node_id)
    REFERENCES nodes (workflow_version_id, id)
);

-- Fast lookup for pgbench clients (seq -> run uuid).
CREATE TABLE bench_run_map (
  seq int PRIMARY KEY,
  run_id uuid NOT NULL REFERENCES workflow_runs(id)
);

-- Node hop ring for deterministic checkpoint advances (10 hops).
CREATE TABLE bench_node_ring (
  hop int PRIMARY KEY CHECK (hop BETWEEN 0 AND 9),
  node_id uuid NOT NULL
);

CREATE INDEX idx_outbox_available
  ON run_node_jobs_outbox (available_at NULLS FIRST, created_at);
