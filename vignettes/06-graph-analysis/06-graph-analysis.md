# Graph Analysis
Simon Frost

## Introduction

Beyond storing and searching knowledge, SST graphs can be *analysed*
structurally. SemanticSpacetime.jl provides tools for building adjacency
matrices, computing eigenvector centrality, and finding topological
features like sources, sinks, and loops. This vignette demonstrates
these graph analysis capabilities.

## Building a Sample Graph

We’ll model a simple food web — a directed graph where edges represent
energy flow from prey to predator:

``` julia
using SemanticSpacetime

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()

# Register arrows
feeds_f = insert_arrow!("LEADSTO", "feeds", "feeds on", "+")
feeds_b = insert_arrow!("LEADSTO", "fed-by", "is fed on by", "-")
insert_inverse_arrow!(feeds_f, feeds_b)

has_f = insert_arrow!("CONTAINS", "has", "contains", "+")
has_b = insert_arrow!("CONTAINS", "in", "is in", "-")
insert_inverse_arrow!(has_f, has_b)

store = MemoryStore()

# Producers (sources — nothing feeds them in this model)
sun = mem_vertex!(store, "sunlight", "producers")
grass = mem_vertex!(store, "grass", "producers")
algae = mem_vertex!(store, "algae", "producers")
mem_edge!(store, sun, "feeds", grass)
mem_edge!(store, sun, "feeds", algae)

# Primary consumers
rabbit = mem_vertex!(store, "rabbit", "consumers")
insect = mem_vertex!(store, "insect", "consumers")
fish = mem_vertex!(store, "small fish", "consumers")
mem_edge!(store, grass, "feeds", rabbit)
mem_edge!(store, grass, "feeds", insect)
mem_edge!(store, algae, "feeds", fish)

# Secondary consumers
fox = mem_vertex!(store, "fox", "predators")
bird = mem_vertex!(store, "bird", "predators")
mem_edge!(store, rabbit, "feeds", fox)
mem_edge!(store, insect, "feeds", bird)
mem_edge!(store, fish, "feeds", bird)

# Top predator (sink — nothing eats it)
eagle = mem_vertex!(store, "eagle", "predators")
mem_edge!(store, fox, "feeds", eagle)
mem_edge!(store, bird, "feeds", eagle)

println("Food web: $(node_count(store)) species, $(link_count(store)) feeding links")
```

    Food web: 9 species, 20 feeding links

## Building an Adjacency Matrix

The `AdjacencyMatrix` is a sparse directed graph representation that
enables structural analysis:

``` julia
adj = SemanticSpacetime.AdjacencyMatrix()

# Add edges from the store's node incidence lists
for (nptr, node) in store.nodes
    for links in node.incidence
        for link in links
            arr = get_arrow_by_ptr(link.arr)
            if arr.short == "feeds"
                SemanticSpacetime.add_edge!(adj, nptr, link.dst, Float64(link.wgt))
            end
        end
    end
end

println("Adjacency matrix: $(length(adj.nodes)) nodes")
println(graph_summary(adj))
```

    Adjacency matrix: 9 nodes
    Graph Summary
    ─────────────
      Nodes:   9
      Links:   10 (directed)
      Sources: 1
      Sinks:   1
      Top centrality:
        (1,8)  0.1111
        (2,1)  0.1111
        (1,3)  0.1111
        (1,1)  0.1111
        (1,5)  0.1111

## Finding Sources and Sinks

**Sources** are nodes with no incoming edges — in our food web, these
are the primary energy sources. **Sinks** are nodes with no outgoing
edges — the top predators.

``` julia
sources = find_sources(adj)
println("Sources (no incoming edges):")
for nptr in sources
    node = mem_get_node(store, nptr)
    if node !== nothing
        println("  '$(node.s)'")
    end
end
```

    Sources (no incoming edges):
      'sunlight'

``` julia
sinks = find_sinks(adj)
println("Sinks (no outgoing edges):")
for nptr in sinks
    node = mem_get_node(store, nptr)
    if node !== nothing
        println("  '$(node.s)'")
    end
end
```

    Sinks (no outgoing edges):
      'eagle'

## Eigenvector Centrality

Eigenvector centrality measures the *importance* of each node based on
the importance of its neighbours. In a food web, high centrality
indicates a species that is central to energy flow.

``` julia
centrality = eigenvector_centrality(adj; max_iter=100, tol=1e-6)

# Sort by centrality score
ranked = sort(collect(centrality), by=x -> x.second, rev=true)

println("Eigenvector centrality (descending):")
for (nptr, score) in ranked
    node = mem_get_node(store, nptr)
    if node !== nothing
        println("  $(rpad(node.s, 20)) $(round(score, digits=4))")
    end
end
```

    Eigenvector centrality (descending):
      eagle                0.1111
      small fish           0.1111
      algae                0.1111
      sunlight             0.1111
      insect               0.1111
      rabbit               0.1111
      fox                  0.1111
      bird                 0.1111
      grass                0.1111

## Detecting Loops

Loops (cycles) in a directed graph indicate feedback or circular
dependencies. Let’s add a cycle to our food web to demonstrate:

``` julia
# Add a decomposition cycle: eagle → soil → grass (nutrient recycling)
soil = mem_vertex!(store, "soil nutrients", "producers")
mem_edge!(store, eagle, "feeds", soil)
mem_edge!(store, soil, "feeds", grass)

# Rebuild adjacency with the cycle
adj2 = SemanticSpacetime.AdjacencyMatrix()
for (nptr, node) in store.nodes
    for links in node.incidence
        for link in links
            arr = get_arrow_by_ptr(link.arr)
            if arr.short == "feeds"
                SemanticSpacetime.add_edge!(adj2, nptr, link.dst, Float64(link.wgt))
            end
        end
    end
end

cycles = detect_loops(adj2)
println("Detected $(length(cycles)) cycle(s):")
for (i, cycle) in enumerate(cycles)
    names = String[]
    for nptr in cycle
        node = mem_get_node(store, nptr)
        if node !== nothing
            push!(names, node.s)
        end
    end
    println("  Cycle $i: ", join(names, " → "))
end
```

    Detected 2 cycle(s):
      Cycle 1: bird → eagle → soil nutrients → grass → insect
      Cycle 2: eagle → soil nutrients → grass → rabbit → fox

## Graph Symmetrization

For some analyses (e.g., community detection), you may want an
undirected graph. The `symmetrize` function creates a symmetric
adjacency matrix:

``` julia
sym_adj = symmetrize(adj2)
println("Original: $(length(adj2.nodes)) nodes")
println("Symmetrized: $(length(sym_adj.nodes)) nodes")

# Centrality on the symmetrized graph
sym_centrality = eigenvector_centrality(sym_adj)
ranked_sym = sort(collect(sym_centrality), by=x -> x.second, rev=true)

println("\nUndirected centrality:")
for (nptr, score) in ranked_sym[1:min(5, length(ranked_sym))]
    node = mem_get_node(store, nptr)
    if node !== nothing
        println("  $(rpad(node.s, 20)) $(round(score, digits=4))")
    end
end
```

    Original: 10 nodes
    Symmetrized: 10 nodes

    Undirected centrality:
      grass                1.0
      eagle                0.7886
      bird                 0.7579
      soil nutrients       0.7023
      insect               0.6902

## Graph Summary

The `graph_summary` function provides a quick overview of graph
statistics:

``` julia
println(graph_summary(adj2))
```

    Graph Summary
    ─────────────
      Nodes:   10
      Links:   12 (directed)
      Sources: 1
      Sinks:   0
      Top centrality:
        (2,2)  1.0000
        (1,5)  0.6000
        (1,4)  0.6000
        (1,2)  0.6000
        (1,8)  0.4000

## ETC Validation on the Graph

We can also run ETC (Event/Thing/Concept) validation across the entire
graph to check for type consistency:

``` julia
issues = validate_graph_types(store)
println("Nodes with ETC issues: $(length(issues))")
for (nptr, warnings) in issues
    node = mem_get_node(store, nptr)
    if node !== nothing
        println("  '$(node.s)':")
        for w in warnings
            println("    - $w")
        end
    end
end
```

    Nodes with ETC issues: 0

## Summary

SemanticSpacetime.jl provides a full suite of graph analysis tools:

| Function                 | Purpose                              |
|--------------------------|--------------------------------------|
| `AdjacencyMatrix`        | Sparse directed graph representation |
| `find_sources`           | Nodes with no incoming edges         |
| `find_sinks`             | Nodes with no outgoing edges         |
| `detect_loops`           | Find cycles in the graph             |
| `eigenvector_centrality` | Rank nodes by structural importance  |
| `symmetrize`             | Convert directed → undirected graph  |
| `graph_summary`          | Quick statistics overview            |
| `validate_graph_types`   | Check ETC type consistency           |

These tools enable structural analysis of SST knowledge graphs —
revealing the topology of knowledge, identifying central concepts, and
detecting circular reasoning.
