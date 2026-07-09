# Graph & Workflow Data Structures

Hands-on Go implementations and notes for building Orchex workflow graphs — from basic DSA concepts to workflow validation.

## Run

From this directory:

```bash
go run .
```

From the repo root:

```bash
go run ./data-structure/
```

Do **not** run `main.go` alone — `Graph` and `WorkflowGraph` live in separate files in the same `package main`.

## Files

| File                | Purpose                                                              |
| ------------------- | -------------------------------------------------------------------- |
| `basics-graph.go`   | Core directed graph: adjacency list, degrees, BFS/DFS, sources/sinks |
| `workflow-graph.go` | Workflow layer: node types, metadata, degree validation              |
| `main.go`           | Demos for both graph and workflow graph                              |
| `go.mod`            | Module root for this learning package                                |

---

## What we learned (in order)

### 1. Graph basics — nodes & edges

A **graph** is `G = (V, E)`:

- **Node (vertex)** — an entity (step ID like `"start"`, `"api"`)
- **Edge** — a connection between two nodes

We store it as a **directed adjacency list**:

```go
adj map[string]map[string]struct{}
```

Each key is a node; its value is the set of outgoing neighbors. Using `map[string]struct{}` gives **O(1)** average edge lookup (set semantics, no duplicates).

| Operation             | Time           | Space        |
| --------------------- | -------------- | ------------ |
| Add node              | O(1) amortized | —            |
| Add edge              | O(1) amortized | —            |
| List neighbors of `u` | O(out-degree)  | —            |
| Overall storage       | —              | **O(n + m)** |

**Key gotcha:** `AddEdge` creates its endpoints, but an **isolated node** (no edges yet) must be added with `AddNode` explicitly.

**Graph vs tree:** A general graph has **no root**. Trees are a special case where you pick one entry point.

---

### 2. Directed vs undirected edges

| Type           | Meaning                 | Orchex                                 |
| -------------- | ----------------------- | -------------------------------------- |
| **Directed**   | `A → B` is one-way      | Yes — `from → to` means execution flow |
| **Undirected** | `A — B` works both ways | No — used only for contrast in DSA     |

Our `AddDirectedEdge(from, to)` only stores `from → to`. Reverse direction requires a separate edge.

---

### 3. In-degree & out-degree

In a **directed** graph:

| Term           | Meaning               | How we compute it                                             |
| -------------- | --------------------- | ------------------------------------------------------------- |
| **Out-degree** | Edges leaving a node  | `len(adj[u])` or cached `outDegrees[u]`                       |
| **In-degree**  | Edges entering a node | Scan all edges, or cached `inDegrees[u]` on `AddDirectedEdge` |

| Node role                      | Typical degrees |
| ------------------------------ | --------------- |
| **Source / entry** (Start)     | in = 0          |
| **Sink / terminal** (Response) | out = 0         |
| **Fan-out (branching)**        | out > 1         |
| **Fan-in (merging)**           | in > 1          |

| Operation                 | Time     |
| ------------------------- | -------- |
| Out-degree query (cached) | O(1)     |
| In-degree query (scan)    | O(n + m) |
| In-degree query (cached)  | O(1)     |

**Go gotcha:** Writing to a `nil` map panics (`assignment to entry in nil map`). Always `make()` degree maps in `NewGraph()`.

---

### 4. Path, reachability & connected components

- **Path** — sequence of nodes connected by directed edges (e.g. `A → B → C`)
- **Reachability** — `v` is reachable from `u` if a path `u ⇝ v` exists
- **Edge ≠ reachability** — `A → B → C` means `A` reaches `C` even without a direct `A → C` edge

Computed with **BFS** or **DFS** from a start node, tracking a `visited` set.

| Algorithm                | Time         | Space    |
| ------------------------ | ------------ | -------- |
| BFS / DFS from one start | **O(n + m)** | **O(n)** |

**Connected components** (directed graphs):

- **Weakly connected** — connected if you ignore edge direction (one blob of wired nodes)
- **Strongly connected** — u reaches v and v reaches u (advanced; less relevant for simple DAG workflows)

For Orchex: every important node should be **reachable from Start**. Orphan nodes on a separate island should fail validation.

---

### 5. Directed graphs as workflows

Workflows map graph concepts to execution:

| Graph concept     | Workflow meaning                                  |
| ----------------- | ------------------------------------------------- |
| Edge `A → B`      | B runs after A (B depends on A)                   |
| Source (in = 0)   | **Start / trigger**                               |
| Sink (out = 0)    | **Response / terminal**                           |
| Fan-out (out > 1) | **Branching** (e.g. Conditional picks one branch) |
| Fan-in (in > 1)   | **Merging** (multiple predecessors)               |

Orchex in-degree / out-degree rules per node type:

| Node Type                    | In-degree | Out-degree |
| ---------------------------- | --------- | ---------- |
| Start                        | 0         | 1          |
| Response                     | 1         | 0          |
| Conditional                  | 1         | 2          |
| Function / API / Integration | 1         | 1          |

---

### 6. WorkflowGraph — composition over inheritance

`WorkflowGraph` embeds `*Graph` and adds workflow metadata:

```go
type WorkflowGraph struct {
    *Graph
    nodes map[string]WorkflowNode
}
```

| Layer               | Stores                                        |
| ------------------- | --------------------------------------------- |
| `*Graph` (embedded) | Structure — edges, degrees, traversal         |
| `nodes` map         | Meaning — node type (Start, API, Response, …) |

**Go embedding** promotes `Graph` methods onto `WorkflowGraph`:

```go
w.AddDirectedEdge("a", "b")  // works — same as w.Graph.AddDirectedEdge(...)
w.BFS("a", "b")              // promoted from *Graph
```

This is **composition**, not classical inheritance — `WorkflowGraph` is not a `*Graph` for type assignment.

**Keep graph and metadata in sync:**

- Add step → `AddNode(id)` + `nodes[id] = WorkflowNode{...}`
- Add wire → `AddDirectedEdge(from, to)` only

`Validate()` checks every graph node has metadata, satisfies degree rules for its type, and rejects cycles.

---

### 7. DAG concepts

**DAG** = **D**irected **A**cyclic **G**raph — a directed graph with **no cycles**.

```text
DAG (OK):              NOT a DAG:

Start → API → Response  A → B → C → A
```

| Without DAG guarantee             | With DAG guarantee                |
| --------------------------------- | --------------------------------- |
| Scheduler may loop forever        | Execution always makes progress   |
| No valid execution order          | Topological sort exists           |
| Broken workflows can be published | Reject on publish if cycle exists |

A **cycle** is a path that starts and ends at the same node (including self-loops like `A → A`). Orchex disallows cycles in the README.

Our graph is directed but **not automatically** a DAG — users can still wire `A → B → C → A`. `IsDAG()` / `HasCycle()` enforce acyclicity at validation time.

---

### 8. Cycle detection — algorithm intuitions

Both `HasCycleDFS()` and `HasCycleKahn()` answer the same question: **can we loop forever?**  
They run in **O(n + m)** time and **O(n)** space. `HasCycle()` uses Kahn by default; both are available for learning and cross-checking.

#### DFS three-color (`HasCycleDFS`)

**Intuition:** Walk along outgoing edges. If you ever reach a node you are **still inside** (still exploring), you’ve found a **back edge** — a loop.

Track each node with a color:

| Color     | Meaning                                           |
| --------- | ------------------------------------------------- |
| **White** | Not visited yet                                   |
| **Gray**  | Currently on the recursion stack (being explored) |
| **Black** | Fully explored — all descendants finished         |

```text
DFS from A on A → B → C → A:

  visit A (gray)
    visit B (gray)
      visit C (gray)
        edge C → A, A is gray  →  CYCLE
```

**Rule:** Edge to a **gray** node → cycle. Edge to **black** → already finished that branch, fine. Edge to **white** → recurse deeper.

**Why it works:** In a DAG, you never revisit an ancestor — you only finish subtrees and mark them black. A cycle forces you to follow dependencies back to something still gray.

**Workflow reading:** “Am I following a chain of dependencies that eventually points back to something I haven’t finished yet?”

#### Kahn’s algorithm (`HasCycleKahn`)

**Intuition:** Simulate execution. A node can run only when all its dependencies are done. **In-degree = number of unfinished dependencies.** Peel nodes with in-degree 0; when you finish one, decrement neighbors’ in-degrees.

```text
1. Queue all nodes with in-degree 0  →  "ready to run"
2. Remove one, decrement each neighbor's in-degree
3. Neighbor hits 0 → add to queue
4. Repeat until queue is empty
```

**If you peeled all n nodes** → no cycle (peel order is a topological order — topic #9).

**If nodes remain** → every leftover node has in-degree ≥ 1, so each waits on another leftover node → mutual blocking → **cycle**.

```text
A → B → C → A

in-degrees: A=1, B=1, C=1  →  queue empty at start  →  cycle
```

```text
Start → API → Response

Peel Start → API in: 1→0 → peel API → Response in: 1→0 → peel Response
Removed 3/3 → DAG
```

**Why decrementing in-degree works:** Each `in[v]--` means “one more dependency of `v` just finished.” That’s exactly what the scheduler needs to know.

**Workflow reading:** “Can the scheduler ever make progress? If nothing has in-degree 0, everyone is waiting on each other.”

#### DFS vs Kahn — when to use which

|                         | DFS three-color                  | Kahn                        |
| ----------------------- | -------------------------------- | --------------------------- |
| Core question           | “Am I walking back into myself?” | “Is anything ready to run?” |
| Style                   | Recursion / depth-first          | BFS / queue, iterative      |
| Also gives topo order   | No (needs extra step)            | Yes (peel order)            |
| Uses cached `inDegrees` | No                               | Yes (copied, not mutated)   |

For Orchex **publish validation**, either is correct. Kahn is a natural fit when you also need **execution order** (topological sort — see §9).

---

### 9. Topological sort — algorithm intuitions

A **topological ordering** lists every node so that for each edge `A → B`, **A appears before B**. That is a valid **execution schedule** for a DAG.

```text
Start → API → Response

Topo order: [Start, API, Response]
```

| Property     | Detail                                                       |
| ------------ | ------------------------------------------------------------ |
| Exists when  | Graph is a DAG (no cycle)                                    |
| Unique?      | Often **no** — parallel branches allow multiple valid orders |
| Time / space | **O(n + m)** / **O(n)** for both algorithms below            |

#### Kahn topological sort (`TopoSortKahn`)

**Intuition:** Same peel as `HasCycleKahn`, but **record** each removed node instead of only counting.

```text
1. Queue nodes with in-degree 0  →  ready to run
2. Remove one, append to order
3. Decrement neighbor in-degrees; enqueue any that hit 0
4. Repeat
```

```text
Start → API → Response

Queue [Start] → order [Start]
Queue [API]   → order [Start, API]
Queue [Response] → order [Start, API, Response]
```

**If `len(order) < n`** → cycle (same stuck-node argument as cycle detection).

**Workflow reading:** “Run whatever has no unfinished dependencies; the peel sequence is one valid schedule.”

#### DFS topological sort (`TopoSortDFS`)

**Intuition:** DFS finishes a node **after** all its descendants. Append nodes in **post-order** (on the way back up), then **reverse** the list.

```text
DFS from Start on Start → API → Response:

  go deep to Response, back up: append Response
  back to API: append API
  back to Start: append Start

  post-order: [Response, API, Start]
  reversed:   [Start, API, Response]  ✓
```

**Why reverse works:** For edge `u → v`, DFS finishes `v` before `u`, so post-order has `v` before `u`. Reversing puts `u` before `v`.

**Cycle check:** Run `HasCycleDFS()` first — on a cycle, post-order alone does not guarantee a valid schedule.

**Workflow reading:** “Finish all downstream work before marking a step done; reverse finish times to respect dependencies.”

#### Kahn vs DFS for topological sort

|                 | Kahn (`TopoSortKahn`)                                       | DFS post-order (`TopoSortDFS`) |
| --------------- | ----------------------------------------------------------- | ------------------------------ |
| Core idea       | Peel ready nodes (in-degree 0)                              | Reverse DFS finish order       |
| Style           | Iterative queue                                             | Recursion                      |
| Cycle handling  | Incomplete order (`ok=false`)                               | `HasCycleDFS()` guard          |
| Scheduler fit   | **Strong** — matches “what can run now”                     | Good for validation / dry-run  |
| Order stability | Depends on queue order; sort queue for deterministic output | Depends on DFS neighbor order  |

`WorkflowGraph.ExecutionOrder()` uses Kahn via promoted `TopoSortKahn()`.

---

## Implemented API summary

### `Graph` (`basics-graph.go`)

| Method                      | Description                              |
| --------------------------- | ---------------------------------------- |
| `NewGraph()`                | Create empty graph with initialized maps |
| `AddNode(id)`               | Register a node with no edges            |
| `AddDirectedEdge(from, to)` | Add directed edge; update in/out degrees |
| `Nodes()`                   | All node IDs (keys of `adj`)             |
| `Edges()`                   | All edges as `"from -> to"` strings      |
| `BFS(start, target)`        | Reachability check via BFS               |
| `DFS(start, target)`        | Reachability check via iterative DFS     |
| `DFSRecursive(start)`       | All nodes reachable from start           |
| `Sources()`                 | Nodes with in-degree 0                   |
| `Sinks()`                   | Nodes with out-degree 0                  |
| `HasCycleDFS()`             | Cycle detection via three-color DFS      |
| `HasCycleKahn()`            | Cycle detection via Kahn's algorithm     |
| `HasCycle()`                | Cycle detection (uses Kahn)              |
| `IsDAG()`                   | `true` when the graph has no cycle       |
| `TopoSortKahn()`            | Topological order via Kahn's peel        |
| `TopoSortDFS()`             | Topological order via DFS post-order     |

### `WorkflowGraph` (`workflow-graph.go`)

| Method                      | Description                                                 |
| --------------------------- | ----------------------------------------------------------- |
| `NewWorkflowGraph()`        | Create graph + empty nodes map                              |
| `AddWorkflowNode(id, type)` | Register node with workflow type                            |
| `Connect(from, to)`         | Add edge between known workflow nodes                       |
| `GetNode(id)`               | Lookup workflow metadata                                    |
| `Validate()`                | Enforce Orchex degree rules per node type and reject cycles |
| `ExecutionOrder()`          | Topological execution order (Kahn)                          |

---

## Study plan complete

Topics covered: graph basics → directed edges → degrees → reachability → workflows → DAG → cycle detection → topological sort.

## Quick reference

```
Graph theory          Workflow (Orchex)
─────────────         ─────────────────
vertex                step / node
directed edge         wire (from → to)
source (in=0)         Start / trigger
sink (out=0)          Response
path                  execution chain
reachable             can run after Start
DAG (no cycles)       publishable workflow
topo sort             execution schedule
```
