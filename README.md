# Orchex

Orchex is a workflow builder. A user draws a flow, publishes it, and asks us to run it reliably.

That sounds simple until the first practical questions arrive. What happens while a user is halfway through drawing an invalid graph? Which version should a run use if the workflow is edited while it is running? If one API call fails after three successful steps, do we start everything again? And how do we keep this understandable when the system grows from a handful of runs to a million a day?

This document tells the story of the design as a conversation between an interviewer and a candidate. It is intentionally separated into functional requirements, non-functional requirements, high-level design, API design, schema design, and the deep dives we will add later.

The design board in [`orchex.excalidraw`](./orchex.excalidraw) is the source of truth. [`schema.dbml`](./schema.dbml) is the PostgreSQL model, [`node-type-schemas`](./node-type-schemas) contains the executable node contracts, and [`data-structure`](./data-structure) contains the graph experiments that informed the design.

- [1. Functional Requirements](#1-functional-requirements)
- [2. Non-Functional Requirements](#2-non-functional-requirements)
- [3. High-Level Design](#3-high-level-design)
- [4. API Design](#4-api-design)
- [5. Schema Design](#5-schema-design)
- [6. Deep-Dive Design — Later](#6-deep-dive-design--later)

## 1. Functional Requirements

### What are we building?

**Interviewer:** What is Orchex, and where do we draw the product boundary?

**Candidate:** We are building a workflow product, not a thin UI over somebody else's orchestrator. Orchex therefore owns:

- workflow definitions and versioning;
- graph validation;
- scheduling one node at a time;
- checkpoints and run state;
- pause, resume, stop, and retry behavior;
- the contract between each node and the next one.

### How is a workflow triggered?

**Interviewer:** Should a workflow start through a webhook, a schedule, or a manual action?

**Candidate:** For v1, a workflow starts manually. Webhooks and schedules are represented in the underlying trigger model so we can add them later, but they are not exposed by the current API.

### How do integrations work?

**Interviewer:** Are we also building the integration catalog and credential system?

**Candidate:** No. We assume integration infrastructure and authentication already exist, and use Composio for Integration Action nodes. Orchex decides when an action executes and how its result moves through the graph; Composio handles the provider-specific action and credentials.

### What does a workflow look like?

**Interviewer:** We have nodes and edges, but what rules turn that graph into a valid workflow?

**Candidate:** The builder stores nodes and directed edges. An edge `A -> B` means that B may run after A. The graph must be a DAG: directed, with no cycles.

We deliberately validate in two stages:

1. **Save is forgiving.** A draft is work in progress. It may be disconnected or incomplete while somebody is drawing it.
2. **Publish is strict.** A published workflow must be non-empty, acyclic, and satisfy the degree rules for every node type.

This separation matters. If every save required a runnable graph, the builder would fight the user. If publish accepted an unfinished graph, the execution engine would inherit a problem it cannot safely solve.

### Which nodes do we support?

**Interviewer:** Which node types are in v1, and how may they connect?

**Candidate:** We support six node types:

- **Start** is an entry-point node: `0` incoming edges and `1` outgoing edge.
- **Conditional** evaluates an expression and chooses one of two branches: `1` incoming and `2` outgoing edges.
- **Function** runs JavaScript: `1` incoming and `1` outgoing edge.
- **General API** makes an HTTP request: `1` incoming and `1` outgoing edge.
- **Integration Action** invokes a Composio action: `1` incoming and `1` outgoing edge.
- **Response** ends the flow: `1` incoming edge and `0` outgoing edges.

Normal edges use the label `default`. The two outgoing edges of a Conditional use `true` and `false`. The database enforces one edge per `(workflow version, source node, label)`, which also prevents two `true` branches from the same Conditional.

Those degree rules also mean v1 has no merge points. After a Conditional branches, each path continues independently; nothing may rejoin with fan-in greater than one. That keeps scheduling and resume simple for now. Join semantics can come later with an explicit node type rather than as a silent graph exception.

Agent, Router, and Scheduler nodes are intentionally deferred. The schema-driven node catalog lets us add them without changing the identity model.

### Why a DAG

**Interviewer:** Why disallow cycles instead of supporting loops immediately?

**Candidate:** A DAG gives us a finite execution path and a valid topological order. More importantly, it keeps v1 recovery understandable: a worker executes a node, stores a checkpoint, and schedules the next node. A cycle would turn that into loop semantics—iteration limits, repeated state, and more complicated retry rules—which is a separate feature rather than a small extension.

The Go implementation in [`data-structure`](./data-structure) demonstrates degree checks, cycle detection, and topological sorting with Kahn's algorithm. Reachability from Start is a useful learning check there, but it is not yet part of the published hard-validation checklist.

### How does draft and publish work?

**Interviewer:** What happens when someone edits a workflow that is already live?

**Candidate:** The most important versioning decision is that “what I am editing” and “what is live” are not always the same thing.

Creating a workflow atomically creates the workflow and an empty draft version 1. While that version is a draft, saves update it in place. Once published, it becomes immutable.

If a user edits again after publishing, the next full `PUT` becomes a new draft version. We do not deep-copy the published graph and then apply a patch: the client already sends the complete graph, so that request is the new snapshot.

Two pointers on `workflows` make this explicit:

- `latest_version_id` points to the editable head;
- `latest_published_version_id` points to the version used by new runs.

Before the first publish, the published pointer is `null`. When there are no unpublished changes, both pointers are equal. When they differ, the builder can show “unpublished changes” without comparing two graphs.

The workflow status describes its wider lifecycle:

- `draft`: it has never been published;
- `published`: it has been published at least once, even if a newer draft now exists;
- `archived`: it has been soft-deleted.

Archiving removes a workflow from normal retrieval and prevents future edits or publishes. There is no unarchive API in v1. Existing runs are different: each run is pinned to a published version, so publishing something newer or archiving the workflow does not rewrite history underneath it.

### How do failures recover?

**Interviewer:** If the fourth node fails after three successful nodes, do we roll back everything?

**Candidate:** No. External actions cannot always be reversed, so full transactional rollback would promise something we cannot reliably deliver. We checkpoint the current node, keep the structured error, and retry that same node in the same run. Atomic whole-workflow rollback is deferred.

### How are node failures presented?

**Interviewer:** What happens when a Conditional receives bad data, a Function throws, an integration token expires, or an API times out or returns non-2xx?

**Candidate:** Every executor fails through a structured node-specific error envelope. It gives the UI a stable error class, code, user-facing message, retryability, and optional remediation details. The run stores that error together with the failing node ID so recovery is explicit rather than hidden in logs.

### What execution controls do users need?

**Interviewer:** Can a running workflow be controlled?

**Candidate:** Yes. A run can be paused, resumed, stopped, or retried, subject to its current state. Pause is soft: an in-flight node finishes, but its successor is not scheduled. Stop moves the run to terminal `cancelled`. Retry is only for `failed` runs and continues from `current_node_id`.

### What do we expose for observability?

**Interviewer:** Do we need full node-level traces from day one?

**Candidate:** We start with workflow-level run state and logs. Detailed node-level traces and long-term analytics come later through ClickHouse. This keeps the operational path small while preserving a clear place to add deeper observability.

## 2. Non-Functional Requirements

### Reliability

**Interviewer:** What reliability guarantee matters most in v1?

**Candidate:** A failed run must be restartable from its checkpoint without replaying successful nodes. Runs are pinned to an immutable published version so later edits cannot change an execution already in progress.

The worker design must eventually make checkpointing and enqueueing the next node atomic—likely through an outbox or equivalent. The durable intermediate run-context shape also still needs to be finalized before resume is production-ready.

### Scale

**Interviewer:** What scale are we designing for?

**Candidate:** The initial assumptions are:

- 100,000 workflows;
- 1 million runs per day;
- roughly 10 new runs per second on average;
- 100 QPS during a 10x start burst;
- about 600 concurrent runs if baseline runs last one minute;
- a stretch target of about 60,000 concurrent runs.

The last figure is a capacity target, not a direct result of `100 starts/sec × 1 minute`. At a one-minute average, 100 QPS gives roughly 6,000 concurrent runs. Reaching 60,000 implies longer-running work, a sustained burst, or both.

### Data and consistency

**Interviewer:** This sounds write-heavy. Where does the data go, and do all reads need immediate consistency?

**Candidate:** PostgreSQL is the OLTP source of truth for definitions, immutable published snapshots, checkpoints, and current run state. ClickHouse is the planned OLAP store for historical logs, node traces, and analytics.

Execution checkpoints need strong correctness. Observability can be eventually consistent; a few milliseconds before a trace appears is acceptable.

### Security and isolation

**Interviewer:** Users can write Function nodes. Do those run inside our workers?

**Candidate:** No. Untrusted JavaScript runs in an isolated Lambda/E2B-like sandbox. The worker owns orchestration, while the sandbox only executes code. In short: rent isolation, not the brain.

### Extensibility

**Interviewer:** Are we locking the system to these six nodes and manual triggers?

**Candidate:** No. Node behavior is schema-driven, and the trigger enum already leaves room for webhooks and schedules. We are keeping the v1 surface small without baking those limitations into the core model.

## 3. High-Level Design

### Which architecture did we choose?

**Interviewer:** Why not use Step Functions or Temporal for the whole system?

**Candidate:** Both are good tools for different products. Step Functions fits an AWS-native internal tool. Temporal fits an internal system that wants a mature durable execution engine. Orchex is itself a workflow-builder product, so it needs to own DAG progression, branching, checkpoints, retries, and the builder semantics.

The selected design is a queue-and-worker control plane, with isolated execution only where a node requires it.

```text
Builder / API client
        |
      HTTPS
        |
  Load balancer
    /         \
Workflow     Workflow
Builder      Execution
service      service
                 |
                Queue
                 |
               Workers
                 |
       executor for node type
```

### How does one node execute?

**Interviewer:** Walk me through a run.

**Candidate:**

1. Starting a run pins a published version, stores the Start checkpoint, and enqueues a node job.
2. A worker receives the job and loads the run plus its pinned graph.
3. It selects the executor for the node type.
4. The executor validates its input and performs one unit of work.
5. On success, the worker checkpoints progress and enqueues the selected successor.
6. On failure, it stores a structured error and leaves `current_node_id` at the node that must be retried.

Queue jobs carry identity—primarily `run_id` and `node_id`—instead of becoming a second database. PostgreSQL remains the source of operational truth.

### How are definition and execution traffic separated?

**Interviewer:** Do workflow editing and workflow execution go through the same service?

**Candidate:** They share the public load balancer but split by intent. The distributed Workflow Builder service handles create, retrieve, update, publish, and archive. The distributed Workflow Execution service handles start, retrieve run, pause, resume, stop, and retry. Each side can scale independently.

## 4. API Design

**Interviewer:** What conventions apply to the whole API?

**Candidate:** All routes use the `/v1` prefix. Authentication is assumed to be handled by middleware and is not part of these payloads.

The API uses optimistic concurrency for workflow editing. Timestamps are UTC ISO-8601 strings. IDs are UUIDs in storage; readable IDs below are examples only.

### Shared shapes

**Interviewer:** Which objects appear repeatedly in the API?

**Candidate:** The API is built around a Workflow, a versioned graph, and a Run.

#### Workflow

```json
{
  "id": "wf_01",
  "name": "Onboarding",
  "description": "User signup flow",
  "status": "published",
  "latest_version_id": "ver_02",
  "latest_published_version_id": "ver_01",
  "created_at": "2026-07-15T08:00:00Z",
  "updated_at": "2026-07-15T09:30:00Z",
  "last_published_at": "2026-07-15T09:00:00Z"
}
```

`description`, `latest_published_version_id`, and `last_published_at` may be `null` when they do not apply.

#### Version graph

```json
{
  "id": "ver_02",
  "version": 2,
  "published_at": null,
  "nodes": [
    {
      "id": "node_start",
      "node_type": "start",
      "name": "Start",
      "config": {},
      "position": { "x": 40, "y": 80 }
    }
  ],
  "edges": [
    {
      "id": "edge_1",
      "from_node_id": "node_start",
      "to_node_id": "node_api",
      "label": "default"
    }
  ]
}
```

Node and edge IDs are generated by the client. They remain stable when a graph is forked into a new version. `position` belongs to the builder layout; it has no execution meaning.

#### Run

```json
{
  "id": "run_01",
  "workflow_id": "wf_01",
  "workflow_version_id": "ver_01",
  "status": "running",
  "trigger_type": "manual",
  "current_node_id": "node_api",
  "error": null,
  "started_at": "2026-07-17T08:00:01Z",
  "paused_at": null,
  "cancelled_at": null,
  "completed_at": null,
  "failed_at": null,
  "created_at": "2026-07-17T08:00:00Z",
  "updated_at": "2026-07-17T08:00:01Z"
}
```

Run status is one of `pending`, `running`, `paused`, `failed`, `completed`, or `cancelled`.

### Workflow endpoints

#### Create

**Interviewer:** How do we create a workflow?

**Candidate:** Creation accepts only workflow metadata. It creates the workflow row and an empty draft v1 atomically.

```http
POST /v1/workflows
```

```json
{
  "name": "Onboarding",
  "description": "User signup flow"
}
```

`description` is optional. The request does not accept a graph.

The response is `201 Created` and contains the Workflow fields plus:

```json
{
  "graph": {
    "id": "ver_01",
    "version": 1,
    "published_at": null,
    "nodes": [],
    "edges": []
  }
}
```

The workflow row and empty v1 are created in one transaction. Validation failures return `400`.

#### List

**Interviewer:** Does the list endpoint return every graph?

**Candidate:** No. It returns lightweight, non-archived summaries so the workflow list does not load complete node and edge snapshots.

```http
GET /v1/workflows
```

The response is `200 OK`:

```json
{
  "items": [
    {
      "id": "wf_01",
      "name": "Onboarding",
      "description": "User signup flow",
      "status": "published",
      "latest_version_id": "ver_02",
      "latest_published_version_id": "ver_01",
      "created_at": "...",
      "updated_at": "...",
      "last_published_at": "...",
      "has_unpublished_changes": true
    }
  ]
}
```

Archived workflows are excluded. This is a summary endpoint, so it does not return nodes or edges. Pagination, filtering, and ordering are not part of the current contract.

#### Retrieve

**Interviewer:** How does the client ask for the editable graph versus the live graph?

**Candidate:** It selects `latest` or `published`; `latest` is the default.

```http
GET /v1/workflows/:id
GET /v1/workflows/:id?version=latest
GET /v1/workflows/:id?version=published
```

`latest` is the default and returns the editable head. `published` returns the live graph. The response is `200 OK` and combines the Workflow and Version graph shapes under a `graph` field.

Requesting `published` before the first publish returns `404`. Archived workflows are unavailable; the current design reserves `404`/`410` for missing or archived resources. Retrieval by an arbitrary version ID is deferred.

#### Update

**Interviewer:** Do we patch individual graph operations?

**Candidate:** No. Like n8n-style editors, the client sends the complete graph as the new truth. Optimistic concurrency prevents one editor from silently overwriting another.

```http
PUT /v1/workflows/:id
```

This is a complete replacement, not a patch:

```json
{
  "expected_latest_version_id": "ver_01",
  "name": "Onboarding",
  "description": "User signup flow",
  "nodes": [
    {
      "id": "node_start",
      "node_type": "start",
      "name": "Start",
      "config": {},
      "position": { "x": 40, "y": 80 }
    },
    {
      "id": "node_api",
      "node_type": "api",
      "name": "Create user",
      "config": {
        "method": "POST",
        "url": "https://example.com/users"
      },
      "position": { "x": 280, "y": 80 }
    }
  ],
  "edges": [
    {
      "id": "edge_1",
      "from_node_id": "node_start",
      "to_node_id": "node_api",
      "label": "default"
    }
  ]
}
```

Saving performs soft validation:

- every `node_type` is known;
- every `config` matches that node type's config schema;
- every edge endpoint exists in the submitted graph;
- node and edge IDs are unique within the version;
- node `name` values are unique within the version;
- `expected_latest_version_id` still matches the server's editable head.

An incomplete graph is allowed here. Same-version edge integrity is also enforced by composite foreign keys in Postgres when the graph is persisted.

If the head is a draft, the server updates it in place. If the head is already published, the submitted graph becomes a new draft version. The response is `200 OK`:

```json
{
  "id": "wf_01",
  "status": "published",
  "latest_version_id": "ver_02",
  "latest_published_version_id": "ver_01",
  "graph": {
    "id": "ver_02",
    "version": 2,
    "published_at": null,
    "nodes": [
      {
        "id": "node_start",
        "node_type": "start",
        "name": "Start",
        "config": {},
        "position": { "x": 40, "y": 80 }
      },
      {
        "id": "node_api",
        "node_type": "api",
        "name": "Create user",
        "config": {
          "method": "POST",
          "url": "https://example.com/users"
        },
        "position": { "x": 280, "y": 80 }
      }
    ],
    "edges": [
      {
        "id": "edge_1",
        "from_node_id": "node_start",
        "to_node_id": "node_api",
        "label": "default"
      }
    ]
  },
  "id_remaps": []
}
```

`graph` is the complete saved head. `id_remaps` reports the rare case where a client ID collides inside the target version and the server has to replace it. The element shape of each remap is not fully specified yet; treat the field as a reserved collision report until we lock the object fields.

Validation failures return `400`, missing or archived workflows return `404`/`410`, and a stale expected version returns `409 Conflict`.

#### Publish

**Interviewer:** What changes when a draft is published?

**Candidate:** The editable head is hard-validated, marked immutable, and becomes the version used by new runs.

```http
POST /v1/workflows/:id/publish
```

```json
{}
```

Publish performs hard validation:

- the graph is not empty;
- it is a DAG (no cycles);
- node degrees match their node types.

Config validity, edge endpoints, and unique IDs remain soft-validation concerns from Update. Same-version edge and checkpoint integrity come from the database foreign keys. Reachability from Start and “exactly one Start” are not yet on the hard-validation checklist.

The response is `200 OK`:

```json
{
  "id": "wf_01",
  "name": "Onboarding",
  "status": "published",
  "latest_version_id": "ver_02",
  "latest_published_version_id": "ver_02",
  "last_published_at": "2026-07-15T09:00:00Z",
  "published_version": {
    "id": "ver_02",
    "version": 2,
    "published_at": "2026-07-15T09:00:00Z"
  }
}
```

The response is intentionally thin; the client already has the graph it published. Publishing a head that is already live is an idempotent `200` no-op. Validation failures return `400`; missing or archived workflows return `404`/`410`.

#### Archive

**Interviewer:** Is delete destructive?

**Candidate:** No. It is a soft archive. The definition becomes unavailable for normal workflow operations, while existing pinned runs may continue.

```http
DELETE /v1/workflows/:id
```

The response is `204 No Content`. This is a soft delete: status becomes `archived`, the workflow disappears from list results, and it can no longer be edited or published. Existing pinned runs may continue. No unarchive endpoint exists in v1.

### Run endpoints

#### Start a run

**Interviewer:** How does execution begin?

**Candidate:** Start pins the latest published version and creates a `pending` run at that version's Start node. The execution contract expects a usable Start node; enforcing exactly one Start during publish remains an explicitly tracked validation gap.

```http
POST /v1/workflows/:workflow_id/runs
```

```json
{}
```

Runtime input is deliberately deferred in v1. The server pins the workflow's `latest_published_version_id`, finds that version's Start node, stores it as `current_node_id`, and returns `201 Created` with a complete Run in `pending`.

A workflow that is missing, archived, still a draft, or has never been published returns `404`. Concurrent runs are allowed. Start-run idempotency is not defined yet.

#### Retrieve a run

**Interviewer:** Can terminal runs still be inspected?

**Candidate:** Yes. Retrieve always returns the complete snapshot, including completed, failed, and cancelled runs.

```http
GET /v1/runs/:run_id
```

The response is `200 OK` with the complete Run snapshot. Runs remain readable in every state, including `completed`, `failed`, and `cancelled`. An unknown run returns `404`.

#### Pause

**Interviewer:** What does pause mean if a node is already running?

**Candidate:** It is a soft pause: finish the in-flight node, checkpoint it, and do not schedule the successor.

```http
POST /v1/runs/:run_id/pause
```

```json
{}
```

Pause is soft. If a worker is already executing a node, it finishes that node and checkpoints it, but does not enqueue the successor.

- `pending` or `running` becomes `paused`;
- already `paused` is an idempotent `200`;
- `completed`, `failed`, or `cancelled` returns `409`.

The `200 OK` response is the complete updated Run with `paused_at` set.

#### Resume

**Interviewer:** Where does a paused run continue?

**Candidate:** It continues in the same run from `current_node_id`.

```http
POST /v1/runs/:run_id/resume
```

```json
{}
```

- `paused` becomes `running` and continues from `current_node_id`;
- already `running` is an idempotent `200`;
- every other state returns `409`.

A failed run uses Retry, not Resume.

#### Stop

**Interviewer:** Can a stopped run be resumed later?

**Candidate:** No. Stop produces terminal `cancelled`. It is intentionally different from Pause.

```http
POST /v1/runs/:run_id/stop
```

```json
{}
```

- `pending`, `running`, or `paused` becomes `cancelled`;
- already `cancelled` is an idempotent `200`;
- `completed` or `failed` returns `409`.

The response is the updated Run with `cancelled_at` set. Cancelled is terminal: it cannot be resumed or retried. Stop remains available even if the parent workflow has since been archived.

#### Retry

**Interviewer:** Does retry create a new run or replay the graph?

**Candidate:** Neither. It clears the failure and re-executes the checkpointed node in the same run.

```http
POST /v1/runs/:run_id/retry
```

```json
{}
```

- `failed` becomes `running`;
- already `running` is an idempotent `200`;
- every other state returns `409`.

Retry clears `error` and re-executes `current_node_id` in the same run. We do not create a second run and we do not replay successful nodes.

### Worker-driven transitions

**Interviewer:** Which state changes happen without an API call?

**Candidate:** Workers make normal execution progress:

- `pending -> running` when a worker accepts the first job;
- `running -> completed` after the terminal node succeeds;
- `running -> failed` when a node error is checkpointed.

`completed` and `cancelled` are terminal. `failed` stays frozen until Retry.

### HTTP errors still to standardize

**Interviewer:** Is the HTTP error contract final?

**Candidate:** Not completely. The design fixes status meanings but does not yet define a shared HTTP error JSON body. It also leaves the final choice between `404` and `410` for archived workflows open. Those are API-contract tasks, not details an implementation should invent independently.

## 5. Schema Design

### Why PostgreSQL and relational tables?

**Interviewer:** A workflow is a graph, so why not put everything in one JSON document or a graph database?

**Candidate:** The graph shape is important, but so are relational guarantees. A run must point to a real published version, an edge must not cross versions, and a checkpoint must belong to the exact graph the run pinned. PostgreSQL gives us those constraints while JSONB handles type-specific node configuration.

### How are node contracts represented?

**Interviewer:** Different node types accept different configuration and runtime data. Do we hard-code every shape in each service?

**Candidate:** No. Every node type owns four JSON Schema 2020-12 documents:

- `config_schema`: what the builder stores for the node;
- `input_schema`: what the executor accepts from upstream;
- `output_schema`: what it passes downstream;
- `error_schema`: how failure is reported.

The schemas live in [`node-type-schemas`](./node-type-schemas) and are seeded into `node_types`. This keeps validation shared between the builder, API, and workers instead of scattering type-specific assumptions through each service.

For every node except Start input, runtime payloads use a top-level `data` field. Start accepts an empty input object with no properties; its output still uses `data.payload`.

**Interviewer:** What does each v1 node contract require?

**Candidate:** Each node keeps its own strict configuration, input, output, and error vocabulary.

### Start

**Interviewer:** What begins the runtime data flow?

**Candidate:** Start has no upstream runtime input and produces the trigger payload.

- Config: optional `description` of 1–512 characters.
- Input: empty object (`additionalProperties: false`, no `data` field).
- Output: `data.payload`, which may be an object, array, string, number, boolean, or `null`.
- Error `type`: `validation | internal`.
- Errors: `INVALID_TRIGGER_PAYLOAD`, `INTERNAL_ERROR`.

### Conditional

**Interviewer:** How is a branch selected?

**Candidate:** Conditional evaluates a boolean expression and annotates the outgoing data with the selected branch.

- Config: required `expression` over `input.data`, up to 4096 characters.
- Input: open object under `data`.
- Output: open object under `data` that includes `data.branch` as `"true"` or `"false"`, while other upstream fields may pass through.
- Error `type`: `validation | operation | internal`.
- Errors: `INVALID_INPUT`, `EXPRESSION_ERROR`, `INTERNAL_ERROR`.

### Function

**Interviewer:** How do we support custom logic without making its output rigid?

**Candidate:** Function executes JavaScript in isolation and may return any JSON value.

- Config: `runtime` is fixed to `js`; `source` is required and may be up to 65,536 characters.
- Timeout: 5 seconds by default, from 1 ms to 300 seconds.
- Input: open object under `data`.
- Output: any JSON value under `data`.
- Error `type`: `validation | operation | timeout | internal`.
- Errors: `INVALID_INPUT`, `RUNTIME_ERROR`, `TIMEOUT`, `INTERNAL_ERROR`.

### General API

**Interviewer:** What does the generic HTTP node need to describe?

**Candidate:** It captures the request template and returns the upstream HTTP response through the common data envelope.

- Config: required `method` and URI-template `url`.
- Methods: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `QUERY`.
- Optional config: headers, query parameters, body template, and timeout.
- Timeout: 30 seconds by default, up to 300 seconds.
- Input: open object under `data`.
- Successful output: `data.status`, `data.headers`, and `data.body`.
- A non-2xx HTTP response becomes an execution error with code `HTTP_NON_2XX` and does not hand off as success to the next node. The output schema still enumerates a broad status set for the successful response shape; the error envelope owns the failure path.
- Error `type`: `validation | api | timeout | rate_limit | internal`.
- Errors: `INVALID_INPUT`, `INVALID_CONFIG`, `HTTP_NON_2XX`, `TIMEOUT`, `NETWORK_ERROR`, `RATE_LIMITED`, `INTERNAL_ERROR`.

### Integration Action

**Interviewer:** How does a provider-specific action fit the same graph model?

**Candidate:** The node delegates the action to Composio but keeps Orchex's normal input, output, timeout, and error contracts.

- Provider: fixed to `composio`.
- Config: uppercase action ID such as `GITHUB_CREATE_ISSUE`, optional templated parameters, and timeout.
- Timeout: 30 seconds by default, up to 300 seconds.
- Input: open object under `data`.
- Output: `data.action` and `data.result`.
- Error `type`: `validation | operation | auth | api | timeout | rate_limit | internal`.
- Errors: `INVALID_INPUT`, `INVALID_CONFIG`, `AUTH_EXPIRED`, `ACTION_FAILED`, `TIMEOUT`, `NETWORK_ERROR`, `RATE_LIMITED`, `INTERNAL_ERROR`.

### Response

**Interviewer:** How does a workflow finish?

**Candidate:** Response turns the final node input into the workflow's HTTP-style result and has no outgoing edge.

- Config: required HTTP status code, optional body template and headers.
- Default status: `200`.
- Input: open object under `data`.
- Output: `data.status_code`, optional `data.headers`, and `data.body`.
- Error `type`: `validation | operation | internal`.
- Errors: `INVALID_INPUT`, `TEMPLATE_ERROR`, `INTERNAL_ERROR`.

### One error shape, specific error vocabularies

**Interviewer:** How can the UI handle errors consistently if every node fails differently?

**Candidate:** Every node uses the same envelope, then narrows `type`, `code`, and `details` for its own executor. Every node error requires:

```json
{
  "type": "api",
  "code": "HTTP_NON_2XX",
  "message": "The upstream API returned 500",
  "retryable": true
}
```

`type` is the error class used for UI routing and retry policy. Each node type restricts it to the enums listed above. `code` is the machine-readable failure reason for that node.

It may also include `description`, `retry_after_ms`, `http_status`, and a node-specific `details` object. `message` is a short user-facing summary; `description` can explain remediation. `retryable` is data, not guesswork in the UI.

At run level, we wrap the node error with its identity:

```json
{
  "node_id": "node_api",
  "error": {
    "type": "api",
    "code": "HTTP_NON_2XX",
    "message": "The upstream API returned 500",
    "retryable": true,
    "http_status": 500,
    "details": {
      "method": "POST",
      "url": "https://example.com/users"
    }
  }
}
```

This value is current operational state. It is cleared on retry or success. It is not intended to become our permanent analytics store.

### PostgreSQL entities

**Interviewer:** Which tables hold the design and active execution state?

**Candidate:** PostgreSQL owns workflow definitions and active run state through six core tables.

### `node_types`

**Interviewer:** Why have a node-type table instead of only an enum?

**Candidate:** This is the seeded catalog of executable node kinds. It stores behavior contracts and degree bounds, not just a name.

- UUID primary key and unique stable `type` slug;
- category: `trigger`, `logic`, `action`, or `terminal`;
- display name and min/max in/out degree;
- config, input, output, and error JSON Schemas;
- creation and update timestamps.

The catalog keeps node behavior extensible while `nodes` stays a generic graph table.

### `workflows`

**Interviewer:** What is the mutable object the user actually sees?

**Candidate:** `workflows` is that container.

- identity, name, optional description, and lifecycle status;
- `latest_version_id`, always present after atomic creation;
- nullable `latest_published_version_id`;
- created, updated, and last-published timestamps.

The two version foreign keys form a circular relationship with `workflow_versions`. Creation therefore uses deferred constraints or one transaction that inserts the workflow, inserts v1, and then sets the pointer.

Workflow names are not unique. Different workflows may reasonably share a human title.

### `workflow_versions`

**Interviewer:** Where do draft and published snapshots live?

**Candidate:** Each `workflow_versions` row is one complete graph snapshot.

- UUID identity and parent workflow;
- integer `version`, monotonic within that workflow;
- `published_at`, where `null` means draft;
- `created_at` and `last_updated_at` (this table uses `last_updated_at`, not `updated_at`).

`(workflow_id, version)` is unique. A partial unique index on `workflow_id WHERE published_at IS NULL` ensures at most one draft per workflow. Published rows are treated as immutable by the application.

### `nodes`

**Interviewer:** How can a client node ID remain stable across v1 and v2?

**Candidate:** A node ID is scoped by its version. Nodes use the composite primary key `(workflow_version_id, id)` and contain:

- client-generated logical ID;
- node type reference;
- unique name within the version;
- schema-validated JSON config;
- optional canvas coordinates;
- timestamps.

That is deliberate: `node_start` may exist in both v1 and v2 because it is the same logical builder node, while each row still belongs to exactly one graph snapshot.

### `workflow_edges`

**Interviewer:** Why keep edges in a separate table instead of self-relations on nodes?

**Candidate:** Separate rows make direction, labels, branching, and future routing behavior explicit.

- client-generated logical ID;
- owning workflow version;
- source and target node IDs;
- `default`, `true`, or `false` label;
- timestamps.

The primary key is `(workflow_version_id, id)`. Composite foreign keys from source and target to `nodes(workflow_version_id, id)` prevent cross-version edges. `(workflow_version_id, from_node_id, label)` is unique.

### `workflow_runs`

**Interviewer:** What is the minimum operational state needed for an execution?

**Candidate:** A run is one execution of one published version. It stores:

- workflow and pinned version IDs;
- state and trigger type;
- non-null `current_node_id` checkpoint;
- nullable structured error;
- timestamps for started, paused, cancelled, completed, and failed events;
- normal creation/update timestamps.

The checkpoint uses a composite foreign key with `workflow_version_id`, so a run cannot point into a different graph. Concurrent runs are valid and no uniqueness constraint attempts to prevent them.

We intentionally do not keep permanent node traces in this OLTP table. PostgreSQL answers “what is true about this active run now?” rather than “show every event this platform has ever produced.”

### Integrity now, performance indexes later

**Interviewer:** Should we add every index we might eventually need?

**Candidate:** Not yet. The v1 indexes encode known invariants:

- unique node-type slug;
- unique version number per workflow;
- at most one draft per workflow;
- unique node name per version;
- one outgoing edge for each source/label pair.

Listing, status, timestamp, foreign-key, and worker-polling indexes depend on real query patterns. They are deferred until those patterns exist rather than added speculatively.

## 6. Deep-Dive Design — Later

**Interviewer:** Are all production details settled in this document?

**Candidate:** No. This README establishes the requirements, boundaries, contracts, and high-level choices. We will add focused deep dives as each subsystem becomes implementation-ready.

Planned deep dives include:

- worker leasing, duplicate delivery, poison messages, and retry backoff;
- durable run context and node-output propagation;
- atomic checkpoint-and-enqueue through an outbox or equivalent;
- pause/stop races and long-running node interruption;
- ClickHouse event, trace, retention, and correlation schemas;
- executor isolation, timeouts, resource limits, and sandbox adapters;
- authorization, tenancy, quotas, and data isolation;
- production query patterns and performance indexes.

**Interviewer:** Which product and API decisions are intentionally deferred?

**Candidate:** Keeping v1 small is part of the design:

- webhook and scheduler trigger APIs;
- Agent, Router, and Scheduler nodes;
- custom user-defined node types;
- multitenancy fields and authorization rules;
- arbitrary historical-version retrieval;
- list pagination and filtering;
- run input and a durable intermediate-context model;
- start-run idempotency keys;
- a standard HTTP error response body;
- one consistent archived-resource status (`404` or `410`);
- exact `id_remaps[]` element shape;
- reachability / exactly-one-Start as hard publish rules;
- narrowing General API `output_schema.status` to 2xx if we want the schema itself to forbid non-2xx success shapes;
- retry limits and backoff policy;
- pause/stop races for long-running nodes;
- atomic checkpoint-and-enqueue/outbox behavior;
- ClickHouse event and trace schemas;
- performance indexes based on production queries;
- transactional rollback.

These are not hidden assumptions. They are the next decisions the design needs.

## Repository Map

**Interviewer:** Where can I inspect the source material behind these decisions?

**Candidate:**

- [`orchex.excalidraw`](./orchex.excalidraw) — authoritative architecture, API, and schema board.
- [`schema.dbml`](./schema.dbml) — PostgreSQL OLTP schema.
- [`node-type-schemas`](./node-type-schemas) — JSON Schema contracts for all six node types.
- [`data-structure`](./data-structure) — Go graph implementation and learning notes.

The design has one recurring principle: let drafts be easy to build, make published workflows safe to run, and never lose the exact point from which a failed run should continue.
