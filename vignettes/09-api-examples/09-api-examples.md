# Go API Examples Ported to Julia
Simon Frost

## Introduction

The Go SSTorytime library includes four API examples demonstrating graph
construction, hub joins, maze solving, and loop-corrected path finding.
This vignette ports each example to Julia using SemanticSpacetime.jl’s
`MemoryStore`, showing how the Go patterns translate idiomatically.

## Setup

``` julia
using SemanticSpacetime

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()

# Register arrows used across examples
then_f = insert_arrow!("LEADSTO", "then", "leads to next", "+")
then_b = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
insert_inverse_arrow!(then_f, then_b)

fwd_f = insert_arrow!("LEADSTO", "fwd", "forward link", "+")
fwd_b = insert_arrow!("LEADSTO", "bwd", "backward link", "-")
insert_inverse_arrow!(fwd_f, fwd_b)

has_f = insert_arrow!("CONTAINS", "has", "contains", "+")
has_b = insert_arrow!("CONTAINS", "in", "is in", "-")
insert_inverse_arrow!(has_f, has_b)

belongs_f = insert_arrow!("CONTAINS", "belongs to", "belongs to", "-")
belongs_b = insert_arrow!("CONTAINS", "owns", "owns", "+")
insert_inverse_arrow!(belongs_b, belongs_f)

println("Arrows registered.")
```

    Arrows registered.

## API Example 1: Mary’s Lamb Story

The Go `API_EXAMPLE_1` creates a nursery-rhyme story graph with
`SST.Vertex()` and `SST.Edge()`, then traces paths forward. Here we do
the same with `mem_vertex!` and `mem_edge!`.

``` julia
store1 = MemoryStore()
chap = "home and away"

n1 = mem_vertex!(store1, "Mary had a little lamb", chap)
n2 = mem_vertex!(store1, "Whose fleece was dull and grey", chap)
n3 = mem_vertex!(store1, "And every time she washed it clean", chap)
n4 = mem_vertex!(store1, "It just went to roll in the hay", chap)
n5 = mem_vertex!(store1, "And when it reached a certain age", chap)
n6 = mem_vertex!(store1, "She'd serve it on a tray", chap)

mem_edge!(store1, n1, "then", n2, String[], 1.0f0)
mem_edge!(store1, n2, "then", n3, String[], 0.5f0)
mem_edge!(store1, n2, "then", n5, String[], 0.5f0)
mem_edge!(store1, n3, "then", n4, String[], 1.0f0)
mem_edge!(store1, n5, "then", n6, String[], 1.0f0)

println("Story graph: $(node_count(store1)) nodes, $(link_count(store1)) links")
```

    Story graph: 6 nodes, 10 links

Now trace the branching narrative with `forward_cone`, mirroring the Go
`GetFwdPathsAsLinks` call:

``` julia
cone = forward_cone(store1, n1.nptr; depth=4)

println("Forward cone from 'Mary had a little lamb':")
println("  Paths: $(length(cone.paths))")
for nptr in cone.supernodes
    node = mem_get_node(store1, nptr)
    if node !== nothing
        println("  → '$(node.s)'")
    end
end
```

    Forward cone from 'Mary had a little lamb':
      Paths: 5
      → 'Whose fleece was dull and grey'
      → 'And every time she washed it clean'
      → 'And when it reached a certain age'

The story branches at line 2 into two endings — exactly as the Go
example shows:

``` julia
result = find_paths(store1, n1.nptr, n4.nptr; max_depth=5)
println("Paths to 'roll in the hay': $(length(result.paths))")
for (i, path) in enumerate(result.paths)
    names = [mem_get_node(store1, p).s for p in path if mem_get_node(store1, p) !== nothing]
    println("  Path $i: ", join(names, " → "))
end

result2 = find_paths(store1, n1.nptr, n6.nptr; max_depth=5)
println("\nPaths to 'serve on a tray': $(length(result2.paths))")
for (i, path) in enumerate(result2.paths)
    names = [mem_get_node(store1, p).s for p in path if mem_get_node(store1, p) !== nothing]
    println("  Path $i: ", join(names, " → "))
end
```

    Paths to 'roll in the hay': 1
      Path 1: Mary had a little lamb → Whose fleece was dull and grey → And every time she washed it clean → It just went to roll in the hay

    Paths to 'serve on a tray': 1
      Path 1: Mary had a little lamb → Whose fleece was dull and grey → And when it reached a certain age → She'd serve it on a tray

## API Example 2: HubJoin

The Go `API_EXAMPLE_2` creates nodes and joins them to a central hub
using `SST.HubJoin()`. In Julia, `hub_join!` requires an `SSTConnection`
(database-backed). We replicate the logic using `mem_vertex!` and
`mem_edge!` to create the same hub pattern in memory.

``` julia
store2 = MemoryStore()

names = ["test_node1", "test_node2", "test_node3"]
weights = Float32[0.2, 0.4, 1.0]
context = ["some", "context", "tags"]

nodes = [mem_vertex!(store2, n, "my chapter") for n in names]

# Create an auto-named hub (like Go's HubJoin with empty name)
hub1 = mem_vertex!(store2, "hub_$(join(names, '_'))", "my chapter")
for (i, node) in enumerate(nodes)
    mem_edge!(store2, node, "then", hub1, context, weights[i])
end
println("Hub 1: '$(hub1.s)' with $(length(nodes)) spokes")

# Create a named hub (like Go's HubJoin with "mummy_node")
hub2 = mem_vertex!(store2, "mummy_node", "my chapter")
for node in nodes
    mem_edge!(store2, node, "belongs to", hub2)
end
println("Hub 2: '$(hub2.s)' with $(length(nodes)) members")

println("Store: $(node_count(store2)) nodes, $(link_count(store2)) links")
```

    Hub 1: 'hub_test_node1_test_node2_test_node3' with 3 spokes
    Hub 2: 'mummy_node' with 3 members
    Store: 5 nodes, 12 links

Inspect the hub structure:

``` julia
for node in nodes
    total = sum(length(ch) for ch in node.incidence)
    println("'$(node.s)': $total connections")
end
```

    'test_node1': 2 connections
    'test_node2': 2 connections
    'test_node3': 2 connections

## API Example 3: Maze Solver

The Go `API_EXAMPLE_3` encodes 9 maze corridors and finds paths from
`maze_a7` to `maze_i6`. We build the same graph in memory and use
`find_paths`:

``` julia
store3 = MemoryStore()

maze_paths = [
    ["maze_a7","maze_b7","maze_b6","maze_c6","maze_c5","maze_b5","maze_b4","maze_a4","maze_a3","maze_b3","maze_c3","maze_d3","maze_d2","maze_e2","maze_e3","maze_f3","maze_f4","maze_e4","maze_e5","maze_f5","maze_f6","maze_g6","maze_g5","maze_g4","maze_h4","maze_h5","maze_h6","maze_i6"],
    ["maze_d1","maze_d2"],
    ["maze_f1","maze_f2","maze_e2"],
    ["maze_f2","maze_g2","maze_h2","maze_h3","maze_g3","maze_g2"],
    ["maze_b1","maze_c1","maze_c2","maze_b2","maze_b1"],
    ["maze_b7","maze_b8","maze_c8","maze_c7","maze_d7","maze_d6","maze_e6","maze_e7","maze_f7","maze_f8"],
    ["maze_d7","maze_d8","maze_e8","maze_e7"],
    ["maze_f7","maze_g7","maze_g8","maze_h8","maze_h7"],
    ["maze_a2","maze_a1"],
]

for corridor in maze_paths
    for leg in 2:length(corridor)
        nfrom = mem_vertex!(store3, corridor[leg-1], "solve maze")
        nto = mem_vertex!(store3, corridor[leg], "solve maze")
        mem_edge!(store3, nfrom, "fwd", nto)
    end
end

println("Maze: $(node_count(store3)) nodes, $(link_count(store3)) links")
```

    Maze: 56 nodes, 112 links

Solve from start to end:

``` julia
start_nodes = mem_get_nodes_by_name(store3, "maze_a7")
end_nodes = mem_get_nodes_by_name(store3, "maze_i6")

if !isempty(start_nodes) && !isempty(end_nodes)
    solutions = find_paths(store3, start_nodes[1].nptr, end_nodes[1].nptr; max_depth=30)
    println("Solutions found: $(length(solutions.paths)) DAG paths, $(length(solutions.loops)) loop paths")
    for (i, path) in enumerate(solutions.paths)
        names = [mem_get_node(store3, p).s for p in path if mem_get_node(store3, p) !== nothing]
        println("  Story $i ($(length(names)) steps): $(names[1]) → ... → $(names[end])")
    end
end
```

    Solutions found: 1 DAG paths, 0 loop paths
      Story 1 (28 steps): maze_a7 → ... → maze_i6

## API Example 4: Loop-Corrected Paths (Double Slit)

The Go `API_EXAMPLE_4` loads `doubleslit.n4l` and finds paths from A1 to
B6 with loop corrections. We build the graph in memory from the N4L
structure:

``` julia
store4 = MemoryStore()

# Build the double-slit graph manually (matching doubleslit.n4l)
edges = [
    ("A1","A2"), ("A1","A3"), ("A2","A5"), ("A3","A5"),
    ("A3","A6"), ("A4","S1"), ("A5","S1"), ("A5","S2"),
    ("A6","S2"), ("S1","B1"), ("S2","B2"), ("S2","B3"),
    ("B1","B4"), ("B2","B4"), ("B2","B5"), ("B3","B5"),
    ("B4","B6"),
]

for (src, dst) in edges
    nfrom = mem_vertex!(store4, src, "double slit example")
    nto = mem_vertex!(store4, dst, "double slit example")
    mem_edge!(store4, nfrom, "fwd", nto)
end

println("Double slit graph: $(node_count(store4)) nodes, $(link_count(store4)) links")
```

    Double slit graph: 14 nodes, 34 links

Find paths with loop detection — the Go version uses colliding
wavefronts; we use `find_paths` which separates DAG paths from loop
corrections:

``` julia
a1_nodes = mem_get_nodes_by_name(store4, "A1")
b6_nodes = mem_get_nodes_by_name(store4, "B6")

if !isempty(a1_nodes) && !isempty(b6_nodes)
    result = find_paths(store4, a1_nodes[1].nptr, b6_nodes[1].nptr; max_depth=10)

    println("-- T R E E --")
    println("DAG paths from A1 to B6: $(length(result.paths))")
    for (i, path) in enumerate(result.paths)
        names = [mem_get_node(store4, p).s for p in path if mem_get_node(store4, p) !== nothing]
        println("  Story $i: ", join(names, " → "))
    end

    println("\n++ L O O P S ++")
    println("Loop corrections: $(length(result.loops))")
    for (i, path) in enumerate(result.loops)
        names = [mem_get_node(store4, p).s for p in path if mem_get_node(store4, p) !== nothing]
        println("  Loop $i: ", join(names, " → "))
    end
end
```

    -- T R E E --
    DAG paths from A1 to B6: 5
      Story 1: A1 → A2 → A5 → S1 → B1 → B4 → B6
      Story 2: A1 → A2 → A5 → S2 → B2 → B4 → B6
      Story 3: A1 → A3 → A5 → S1 → B1 → B4 → B6
      Story 4: A1 → A3 → A5 → S2 → B2 → B4 → B6
      Story 5: A1 → A3 → A6 → S2 → B2 → B4 → B6

    ++ L O O P S ++
    Loop corrections: 0

Explore the cone structure to see how the wavefronts expand:

``` julia
if !isempty(a1_nodes)
    for d in [2, 3, 4, 5]
        fwd_cone = forward_cone(store4, a1_nodes[1].nptr; depth=d)
        println("Forward cone depth $d: $(length(fwd_cone.supernodes)) supernodes, $(length(fwd_cone.paths)) paths")
    end
end
```

    Forward cone depth 2: 3 supernodes, 5 paths
    Forward cone depth 3: 6 supernodes, 10 paths
    Forward cone depth 4: 9 supernodes, 18 paths
    Forward cone depth 5: 11 supernodes, 29 paths

## Summary

These four Go API examples translate naturally to Julia:

| Go API | Julia Equivalent |
|----|----|
| `SST.Vertex(sst, name, chap)` | `mem_vertex!(store, name, chap)` |
| `SST.Edge(sst, from, arrow, to, ctx, w)` | `mem_edge!(store, from, arrow, to, ctx, w)` |
| `SST.HubJoin(sst, name, chap, ptrs, arrow, ctx, w)` | Manual hub pattern with `mem_vertex!` + `mem_edge!` |
| `SST.GetFwdPathsAsLinks(sst, ptr, st, depth, limit)` | `forward_cone(store, ptr; depth=d)` |
| `SST.GetPathsAndSymmetries(sst, left, right, ...)` | `find_paths(store, from, to; max_depth=d)` |
| `SST.WaveFrontsOverlap(sst, left, right, ...)` | `find_paths` separates `.paths` from `.loops` |
