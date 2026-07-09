package main

import "fmt"

type Graph struct {
	adj map[string]map[string]struct{} // adjacency list
	inDegrees map[string]int
	outDegrees map[string]int
}

func (g *Graph) AddNode(node string) {
	if _, ok := g.adj[node]; !ok {
		g.adj[node] = map[string]struct{}{}
	}
}

func (g *Graph) AddDirectedEdge(node1, node2 string) { 
	g.AddNode(node1)
	g.AddNode(node2)
	if _, ok := g.adj[node1][node2]; ok {
		return // edge already exists
	}

	g.adj[node1][node2] = struct{}{}
	g.outDegrees[node1]++
	g.inDegrees[node2]++

}

func NewGraph() *Graph {
	return &Graph{
		adj: map[string]map[string]struct{}{},
		outDegrees: map[string]int{},
		inDegrees: map[string]int{},
	}
}

func (g *Graph) Nodes() []string { 
	nodes := make([]string, 0, len(g.adj))
	for node := range g.adj {
		nodes = append(nodes, node)
	}
	return nodes
}

func (g *Graph) Edges() []string { 
	result := make([]string, 0, len(g.adj))

	for node, edges := range g.adj {
		for edge := range edges {
			result = append(result, fmt.Sprintf("%s -> %s", node, edge))
		}
	}
	return result
}

func (g *Graph) hasDirectedEdge(node1, node2 string) bool { 
	_, ok := g.adj[node1][node2]
	return ok
}

func (g *Graph) PrintGraph() { 
	for node, edges := range g.adj {
		fmt.Printf("%s -> %v\n", node, edges)
	}
}


func (g *Graph) outDegree(node string) int { 
	return len(g.adj[node])
}

func (g *Graph) inDegree(node string) int { 
	count := 0
	for _, edges := range g.adj {
		if _, ok := edges[node]; ok {
			count++
		}
	}
	return count
}

func (g *Graph) BFS(start, target string) bool {
	if start == target {
		return true
	}
	visited := map[string]bool{start: true}
	queue := []string{start}

	for len(queue) > 0 {
		u := queue[0]
		queue = queue[1:]

		for v := range g.adj[u] {
			if v == target {
				return true
			}
			if !visited[v] {
				visited[v] = true
				queue = append(queue, v)
			}
		}
	}

	return false
}

func (g *Graph) DFS(start, target string) bool {
    // iterative DFS
	visited := map[string]bool{start: true}
	stack := []string{start}

	for len(stack) > 0 {
		u := stack[len(stack)-1]
		stack = stack[:len(stack)-1]

		if u == target {
			return true
		}

		// To control DFS node visit order as "left to right" for adjacent nodes (i.e., first neighbor in map first on stack)
		// we need to collect neighbors into a slice and push them in reverse order
		neighbors := make([]string, 0, len(g.adj[u]))
		for v := range g.adj[u] {
			if !visited[v] {
				visited[v] = true
				neighbors = append(neighbors, v)
			}
		}
		
		for i := len(neighbors) - 1; i >= 0; i-- {
			stack = append(stack, neighbors[i])
		}
	}
	return false
}

func (g *Graph) DFSRecursive(start string) map[string]bool {
	visited := map[string]bool{}
	var dfs func(u string)
	dfs = func(u string) {
		if visited[u] {
			return
		}
		visited[u] = true
		for v := range g.adj[u] {
			dfs(v)
		}
	}

	dfs(start)

	return visited
}

func (g *Graph) Sources() []string {
	var sources []string
	for u := range g.adj {
		if g.inDegrees[u] == 0 { // or g.inDegree(u) == 0
			sources = append(sources, u)
		}
	}
	return sources
}

func (g *Graph) Sinks() []string {
	var sinks []string
	for u := range g.adj {
		if g.outDegrees[u] == 0 { // or g.outDegree(u) == 0
			sinks = append(sinks, u)
		}
	}
	return sinks
}

type visitState int

const (
	white visitState = iota
	gray
	black
)

// HasCycleDFS detects a cycle using three-color DFS (white/gray/black).
// A back edge to a gray node means a cycle exists.
func (g *Graph) HasCycleDFS() bool {
	state := make(map[string]visitState, len(g.adj))
	for u := range g.adj {
		state[u] = white
	}

	var dfs func(u string) bool
	dfs = func(u string) bool {
		state[u] = gray
		for v := range g.adj[u] {
			switch state[v] {
			case gray:
				return true
			case white:
				if dfs(v) {
					return true
				}
			}
		}
		state[u] = black
		return false
	}

	for u := range g.adj {
		if state[u] == white && dfs(u) {
			return true
		}
	}
	return false
}

// HasCycleKahn detects a cycle by repeatedly removing in-degree-0 nodes.
// If not all nodes are removed, the remaining nodes lie on a cycle.
func (g *Graph) HasCycleKahn() bool {
	in := make(map[string]int, len(g.adj))
	for u := range g.adj {
		in[u] = g.inDegrees[u]
	}

	queue := make([]string, 0)
	for u := range g.adj {
		if in[u] == 0 {
			queue = append(queue, u)
		}
	}

	removed := 0
	for len(queue) > 0 {
		u := queue[0]
		queue = queue[1:]
		removed++

		for v := range g.adj[u] {
			in[v]--
			if in[v] == 0 {
				queue = append(queue, v)
			}
		}
	}

	return removed != len(g.adj)
}

// HasCycle reports whether the graph contains a directed cycle.
func (g *Graph) HasCycle() bool {
	return g.HasCycleKahn()
}

// IsDAG reports whether the graph is a directed acyclic graph.
func (g *Graph) IsDAG() bool {
	return !g.HasCycle()
}

// TopoSortKahn returns a topological ordering by repeatedly peeling in-degree-0 nodes.
// Returns ok=false when the graph contains a cycle.
func (g *Graph) TopoSortKahn() ([]string, bool) {
	in := make(map[string]int, len(g.adj))
	for u := range g.adj {
		in[u] = g.inDegrees[u]
	}

	queue := make([]string, 0)
	for u := range g.adj {
		if in[u] == 0 {
			queue = append(queue, u)
		}
	}

	order := make([]string, 0, len(g.adj))
	for len(queue) > 0 {
		u := queue[0]
		queue = queue[1:]
		order = append(order, u)

		for v := range g.adj[u] {
			in[v]--
			if in[v] == 0 {
				queue = append(queue, v)
			}
		}
	}

	if len(order) != len(g.adj) {
		return nil, false
	}
	return order, true
}

// TopoSortDFS returns a topological ordering via DFS post-order (reversed finish times).
// Returns ok=false when the graph contains a cycle.
func (g *Graph) TopoSortDFS() ([]string, bool) {
	if g.HasCycleDFS() {
		return nil, false
	}

	visited := make(map[string]bool, len(g.adj))
	order := make([]string, 0, len(g.adj))

	var dfs func(u string)
	dfs = func(u string) {
		if visited[u] {
			return
		}
		visited[u] = true
		for v := range g.adj[u] {
			dfs(v)
		}
		order = append(order, u)
	}

	for u := range g.adj {
		dfs(u)
	}

	for i, j := 0, len(order)-1; i < j; i, j = i+1, j-1 {
		order[i], order[j] = order[j], order[i]
	}
	return order, true
}

// func (g *Graph) Degrees() (in, out map[string]int) {
// 	in = make(map[string]int, len(g.adj))
// 	out = make(map[string]int, len(g.adj))
// 	for u := range g.adj {
// 		in[u] = 0
// 		out[u] = 0
// 	}
// 	for u, tos := range g.adj {
// 		out[u] = len(tos)
// 		for v := range tos {
// 			in[v]++
// 		}
// 	}

// 	return in, out
// }

// func (g *Graph) Sources() []string { // in-degree 0
// 	in, _ := g.Degrees()
// 	var src []string
// 	for u, d := range in {
// 		if d == 0 {
// 			src = append(src, u)
// 		}
// 	}
// 	return src
// }

// func (g *Graph) Sinks() []string { // out-degree 0
// 	_, out := g.Degrees()
// 	var sink []string
// 	for u, d := range out {
// 		if d == 0 {
// 			sink = append(sink, u)
// 		}
// 	}
// 	return sink
// }