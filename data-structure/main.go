package main

import "fmt"

func main() {
	demoBasicGraph()
	demoCycleDetection()
	demoTopologicalSort()
	demoWorkflowGraph()
	demoCyclicWorkflow()
}

func demoBasicGraph() {
	fmt.Println("--- Graph demo ---")

	g := NewGraph()
	g.AddNode("A")
	g.AddNode("B")
	g.AddNode("C")
	g.AddDirectedEdge("A", "B")
	g.AddDirectedEdge("B", "C")
	g.PrintGraph()
	fmt.Println(g.Nodes())
	fmt.Println(g.Edges())
	fmt.Println(g.hasDirectedEdge("A", "B"))
	fmt.Println(g.hasDirectedEdge("B", "A"))
	fmt.Println(g.hasDirectedEdge("B", "C"))
	fmt.Println(g.hasDirectedEdge("C", "B"))

	fmt.Println("Out Degree of A:", g.outDegree("A"))
	fmt.Println("Out Degree of B:", g.outDegree("B"))
	fmt.Println("Out Degree of C:", g.outDegree("C"))
	fmt.Println("In Degree of A:", g.inDegree("A"))
	fmt.Println("In Degree of B:", g.inDegree("B"))
	fmt.Println("In Degree of C:", g.inDegree("C"))
	fmt.Println("Out Degrees:", g.outDegrees)
	fmt.Println("In Degrees:", g.inDegrees)

	fmt.Println("BFS from A to C:", g.BFS("A", "C"))
	fmt.Println("DFS from A to C:", g.DFS("A", "C"))
	fmt.Println("DFSRecursive from A:", g.DFSRecursive("A"))
	fmt.Println("DFSRecursive from B:", g.DFSRecursive("B"))
	fmt.Println("DFSRecursive from C:", g.DFSRecursive("C"))

	fmt.Println("Sources:", g.Sources())
	fmt.Println("Sinks:", g.Sinks())
}

func demoCycleDetection() {
	fmt.Println("--- Cycle detection demo ---")

	acyclic := NewGraph()
	acyclic.AddDirectedEdge("A", "B")
	acyclic.AddDirectedEdge("B", "C")
	fmt.Println("A->B->C HasCycleDFS:", acyclic.HasCycleDFS())
	fmt.Println("A->B->C HasCycleKahn:", acyclic.HasCycleKahn())
	fmt.Println("A->B->C IsDAG:", acyclic.IsDAG())

	cyclic := NewGraph()
	cyclic.AddDirectedEdge("A", "B")
	cyclic.AddDirectedEdge("B", "C")
	cyclic.AddDirectedEdge("C", "A")
	fmt.Println("A->B->C->A HasCycleDFS:", cyclic.HasCycleDFS())
	fmt.Println("A->B->C->A HasCycleKahn:", cyclic.HasCycleKahn())
	fmt.Println("A->B->C->A IsDAG:", cyclic.IsDAG())
}

func demoTopologicalSort() {
	fmt.Println("--- Topological sort demo ---")

	g := NewGraph()
	g.AddDirectedEdge("A", "B")
	g.AddDirectedEdge("B", "C")

	kahn, kahnOK := g.TopoSortKahn()
	dfs, dfsOK := g.TopoSortDFS()
	fmt.Println("A->B->C TopoSortKahn:", kahn, kahnOK)
	fmt.Println("A->B->C TopoSortDFS:", dfs, dfsOK)

	cyclic := NewGraph()
	cyclic.AddDirectedEdge("A", "B")
	cyclic.AddDirectedEdge("B", "C")
	cyclic.AddDirectedEdge("C", "A")

	kahnCyclic, kahnCyclicOK := cyclic.TopoSortKahn()
	dfsCyclic, dfsCyclicOK := cyclic.TopoSortDFS()
	fmt.Println("A->B->C->A TopoSortKahn:", kahnCyclic, kahnCyclicOK)
	fmt.Println("A->B->C->A TopoSortDFS:", dfsCyclic, dfsCyclicOK)
}

func demoWorkflowGraph() {
	fmt.Println("--- WorkflowGraph demo ---")

	w := NewWorkflowGraph()
	w.AddWorkflowNode("start", NodeStart)
	w.AddWorkflowNode("api", NodeAPI)
	w.AddWorkflowNode("response", NodeResponse)

	if err := w.Connect("start", "api"); err != nil {
		fmt.Println("connect error:", err)
		return
	}
	if err := w.Connect("api", "response"); err != nil {
		fmt.Println("connect error:", err)
		return
	}

	w.PrintGraph()
	fmt.Println("Sources:", w.Sources())
	fmt.Println("Sinks:", w.Sinks())
	fmt.Println("Reachable from start:", w.DFSRecursive("start"))

	if err := w.Validate(); err != nil {
		fmt.Println("validation failed:", err)
		return
	}
	fmt.Println("validation passed")

	order, err := w.ExecutionOrder()
	if err != nil {
		fmt.Println("execution order error:", err)
		return
	}
	fmt.Println("Execution order:", order)
}

func demoCyclicWorkflow() {
	fmt.Println("--- Cyclic workflow demo (should fail validation) ---")

	w := NewWorkflowGraph()
	w.AddWorkflowNode("a", NodeAPI)
	w.AddWorkflowNode("b", NodeAPI)
	w.AddWorkflowNode("c", NodeAPI)

	_ = w.Connect("a", "b")
	_ = w.Connect("b", "c")
	_ = w.Connect("c", "a")

	fmt.Println("HasCycleDFS:", w.HasCycleDFS())
	fmt.Println("HasCycleKahn:", w.HasCycleKahn())

	if err := w.Validate(); err != nil {
		fmt.Println("validation failed:", err)
		return
	}
	fmt.Println("validation passed")
}
