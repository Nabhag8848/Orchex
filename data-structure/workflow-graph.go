package main

import "fmt"

type NodeType string

const (
	NodeStart       NodeType = "start"
	NodeConditional NodeType = "conditional"
	NodeFunction    NodeType = "function"
	NodeAPI         NodeType = "api"
	NodeIntegration NodeType = "integration"
	NodeResponse    NodeType = "response"
)

type WorkflowNode struct {
	ID   string
	Type NodeType
}

// WorkflowGraph embeds *Graph for structure (edges, degrees, traversal)
// and keeps workflow metadata (node type) in nodes.
type WorkflowGraph struct {
	*Graph
	nodes map[string]WorkflowNode
}

func NewWorkflowGraph() *WorkflowGraph {
	return &WorkflowGraph{
		Graph: NewGraph(),
		nodes: make(map[string]WorkflowNode),
	}
}

func (w *WorkflowGraph) AddWorkflowNode(id string, t NodeType) {
	w.AddNode(id)
	w.nodes[id] = WorkflowNode{ID: id, Type: t}
}

func (w *WorkflowGraph) Connect(from, to string) error {
	if _, ok := w.nodes[from]; !ok {
		return fmt.Errorf("unknown source node %q", from)
	}
	if _, ok := w.nodes[to]; !ok {
		return fmt.Errorf("unknown target node %q", to)
	}
	w.AddDirectedEdge(from, to)
	return nil
}

func (w *WorkflowGraph) GetNode(id string) (WorkflowNode, bool) {
	n, ok := w.nodes[id]
	return n, ok
}

func (w *WorkflowGraph) WorkflowNodes() []WorkflowNode {
	out := make([]WorkflowNode, 0, len(w.nodes))
	for _, n := range w.nodes {
		out = append(out, n)
	}
	return out
}

func (w *WorkflowGraph) validateNodeDegrees(id string) error {
	n := w.nodes[id]
	in := w.inDegrees[id]
	out := w.outDegrees[id]

	switch n.Type {
	case NodeStart:
		if in != 0 || out != 1 {
			return fmt.Errorf("start node %q: want in-degree=0 out-degree=1, got in=%d out=%d", id, in, out)
		}
	case NodeResponse:
		if in != 1 || out != 0 {
			return fmt.Errorf("response node %q: want in-degree=1 out-degree=0, got in=%d out=%d", id, in, out)
		}
	case NodeConditional:
		if in != 1 || out != 2 {
			return fmt.Errorf("conditional node %q: want in-degree=1 out-degree=2, got in=%d out=%d", id, in, out)
		}
	case NodeFunction, NodeAPI, NodeIntegration:
		if in != 1 || out != 1 {
			return fmt.Errorf("%s node %q: want in-degree=1 out-degree=1, got in=%d out=%d", n.Type, id, in, out)
		}
	default:
		return fmt.Errorf("node %q: unknown type %q", id, n.Type)
	}
	return nil
}

// Validate checks that every workflow node is registered in the graph
// and satisfies Orchex in-degree / out-degree rules.
func (w *WorkflowGraph) Validate() error {
	for id := range w.adj {
		if _, ok := w.nodes[id]; !ok {
			return fmt.Errorf("graph node %q has no workflow metadata", id)
		}
	}
	for id := range w.nodes {
		if err := w.validateNodeDegrees(id); err != nil {
			return err
		}
	}
	if w.HasCycle() {
		return fmt.Errorf("workflow contains a cycle")
	}
	return nil
}

// ExecutionOrder returns a topological execution order for the workflow.
func (w *WorkflowGraph) ExecutionOrder() ([]string, error) {
	order, ok := w.TopoSortKahn()
	if !ok {
		return nil, fmt.Errorf("workflow contains a cycle")
	}
	return order, nil
}
