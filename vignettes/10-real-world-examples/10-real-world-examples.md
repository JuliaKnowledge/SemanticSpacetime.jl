# Real-World N4L Examples
Simon Frost

## Introduction

The SSTorytime project ships with a rich collection of N4L example files
covering domains from poetry to physics. This vignette loads, compiles,
and analyses four of these real-world examples, demonstrating the full
parse→compile→analyse pipeline.

## Setup

``` julia
using SemanticSpacetime

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()

const SST_CONFIG = joinpath(@__DIR__, "..", "..", "..", "SSTorytime", "SSTconfig")
const EXAMPLES = joinpath(@__DIR__, "..", "..", "..", "SSTorytime", "examples")
println("Config available: ", isdir(SST_CONFIG))
println("Examples available: ", isdir(EXAMPLES))
```

    Config available: true
    Examples available: true

## Example 1: Mary Had a Little Lamb

The `Mary.n4l` file uses N4L’s sequence mode to tell the classic nursery
rhyme, with annotations and cross-references.

``` julia
mary_text = read(joinpath(EXAMPLES, "Mary.n4l"), String)
println("--- Mary.n4l ---")
println(strip(mary_text))
```

    --- Mary.n4l ---
    -high brow poetry about Mary

     +:: _sequence_ , Mary had a little lamb, poem ::   // starting sequence mode

    @title Mary had a little lamb  (note) Had means possessed not gave birth to
                  "                (written by) Mary's mum

           Whose fleece was white as snow
           And everywhere that Mary went

           // no need to be contiguous

           The lamb was sure to go        (note) SatNav invented later

     -:: _sequence_ ::          // ending sequence mode

     $title.1 (is an example of) Nursery rhyme

``` julia
store1 = MemoryStore()
try
    cr1 = compile_n4l_string!(store1, mary_text; config_dir=SST_CONFIG)
    println("Nodes: $(cr1.nodes_created), Edges: $(cr1.edges_created)")
    println("Chapters: ", join(cr1.chapters, ", "))
catch e
    println("Compilation note: ", e)
end

println("\nGraph: $(node_count(store1)) nodes, $(link_count(store1)) links")
```

    Nodes: 9, Edges: 9
    Chapters: high brow poetry about Mary

    Graph: 9 nodes, 18 links

Explore the compiled graph:

``` julia
for name in ["Mary had a little lamb", "Whose fleece was white as snow", "Nursery rhyme"]
    nodes = mem_get_nodes_by_name(store1, name)
    if !isempty(nodes)
        println("Found: '$(nodes[1].s)' in chapter '$(nodes[1].chap)'")
    end
end
```

    Found: 'Mary had a little lamb' in chapter 'high brow poetry about Mary'
    Found: 'Whose fleece was white as snow' in chapter 'high brow poetry about Mary'
    Found: 'Nursery rhyme' in chapter 'high brow poetry about Mary'

## Example 2: Double-Slit Interference (doors.n4l)

The `doors.n4l` file models a multi-slit interference pattern — multiple
paths from “start” through doors/ports/holes/gates to targets.

``` julia
doors_text = read(joinpath(EXAMPLES, "doors.n4l"), String)
println("--- doors.n4l ---")
println(strip(doors_text))
```

    --- doors.n4l ---
    - multi slit interference

     :: physics, connectivity, path example ::

    start  (fwd) door
        "  (fwd) port
        "  (fwd) hole
        "  (fwd) gate

    door (fwd) passage
      "  (fwd) road
      "  (fwd) river

    port (fwd) river
      "  (fwd) tram

    hole (fwd) tram

    gate (fwd) tram
      "  (fwd) bike

    passage (fwd) target 1
    road    (fwd) target 2

    river  (fwd) target 3
    tram   (fwd)  "
    bike   (fwd)   "

``` julia
store2 = MemoryStore()
try
    cr2 = compile_n4l_string!(store2, doors_text; config_dir=SST_CONFIG)
    println("Nodes: $(cr2.nodes_created), Edges: $(cr2.edges_created)")
catch e
    println("Compilation note: ", e)
end

println("Graph: $(node_count(store2)) nodes, $(link_count(store2)) links")
```

    Nodes: 13, Edges: 17
    Graph: 13 nodes, 34 links

Trace paths from start to targets using cone search and path solving:

``` julia
start_nodes = mem_get_nodes_by_name(store2, "start")
if !isempty(start_nodes)
    cone = forward_cone(store2, start_nodes[1].nptr; depth=5)
    println("Forward cone from 'start': $(length(cone.supernodes)) supernodes")
    for nptr in cone.supernodes
        node = mem_get_node(store2, nptr)
        if node !== nothing
            println("  → '$(node.s)'")
        end
    end
end
```

    Forward cone from 'start': 10 supernodes
      → 'door'
      → 'port'
      → 'hole'
      → 'gate'
      → 'passage'
      → 'road'
      → 'river'
      → 'tram'
      → 'bike'
      → 'target 3'

``` julia
for target_name in ["target 1", "target 2", "target 3"]
    targets = mem_get_nodes_by_name(store2, target_name)
    if !isempty(start_nodes) && !isempty(targets)
        result = find_paths(store2, start_nodes[1].nptr, targets[1].nptr; max_depth=6)
        println("Paths to '$target_name': $(length(result.paths)) DAG, $(length(result.loops)) loops")
        for (i, path) in enumerate(result.paths)
            names = [mem_get_node(store2, p).s for p in path if mem_get_node(store2, p) !== nothing]
            println("  Path $i: ", join(names, " → "))
        end
    end
end
```

    Paths to 'target 1': 1 DAG, 0 loops
      Path 1: start → door → passage → target 1
    Paths to 'target 2': 1 DAG, 0 loops
      Path 1: start → door → road → target 2
    Paths to 'target 3': 6 DAG, 0 loops
      Path 1: start → door → river → target 3
      Path 2: start → port → river → target 3
      Path 3: start → port → tram → target 3
      Path 4: start → hole → tram → target 3
      Path 5: start → gate → tram → target 3
      Path 6: start → gate → bike → target 3

## Example 3: Astronomy Poem

The `astronomy.n4l` file is a playful poem with number-word
substitutions and annotations. It demonstrates EXPRESS arrows for
commentary.

``` julia
astro_text = read(joinpath(EXAMPLES, "astronomy.n4l"), String)

store3 = MemoryStore()
try
    cr3 = compile_n4l_string!(store3, astro_text; config_dir=SST_CONFIG)
    println("Nodes: $(cr3.nodes_created), Edges: $(cr3.edges_created)")
    println("Chapters: ", join(cr3.chapters, ", "))
catch e
    println("Compilation note: ", e)
end

println("Graph: $(node_count(store3)) nodes, $(link_count(store3)) links")
```

    Nodes: 27, Edges: 27
    Chapters: Astronomy by the numbers poem
    Graph: 27 nodes, 54 links

Compute eigenvector centrality to find the most connected concepts:

``` julia
adj = SemanticSpacetime.AdjacencyMatrix()
for (nptr, node) in store3.nodes
    for links in node.incidence
        for link in links
            SemanticSpacetime.add_edge!(adj, nptr, link.dst, Float64(link.wgt))
        end
    end
end

if !isempty(adj.nodes)
    centrality = eigenvector_centrality(adj; max_iter=100, tol=1e-6)
    ranked = sort(collect(centrality), by=x -> x.second, rev=true)
    println("Top nodes by eigenvector centrality:")
    for (nptr, score) in ranked[1:min(8, length(ranked))]
        node = mem_get_node(store3, nptr)
        if node !== nothing
            println("  $(rpad(node.s[1:min(40,length(node.s))], 42)) $(round(score, digits=4))")
        end
    end
end
```

    Top nodes by eigenvector centrality:
      The Moon affects the sur5 heard            1.0
      Moon                                       0.9578
      By law of phy6 great                       0.659
      And makes a year 4 you                     0.6394
      We soon should come to 0                   0.5564
      Astronomy                                  0.5143
      It7 when the stars so bright               0.4253
      sur5 becomes "surf I've"                   0.3939

## Example 4: Friends and Fiends (Social Network)

The `FriendsAndFiends.n4l` file encodes a social network with friend
links and employer relationships.

``` julia
friends_text = read(joinpath(EXAMPLES, "FriendsAndFiends.n4l"), String)
println("--- FriendsAndFiends.n4l ---")
println(strip(friends_text))
```

    --- FriendsAndFiends.n4l ---
    - friend network

    Mark (fr)  Mandy 
      "  (fr)  Silvy
      "  (fr)  Brent
      "  (fr)  Zhao
      "  (fr)  Doug
      "  (fr)  Tore
      "  (fr)  Joyce
      "  (fr)  Mike
      "  (fr)  Carol
      "  (fr)  Ali
      "  (fr)  Matt
      "  (fr)  Bjørn
      "  (fr)  Tamar
      "  (fr)  Kat
      "  (fr)  Hans


    Mike (fr) Mark
      "  (fr) Jane1
      "  (fr) Jane2
      "  (fr) Jan
      "  (fr) Alfie
      "  (fr) Jungi
      "  (fr) Peter
      "  (fr) Paul

    Jan  (fr) Adam 
      "  (fr) Jane1
      "  (fr) Jane


    Adam (fr) Company of Friends
      "  (fr) Paul
      "  (fr) Matt
      "  (fr) Billie
      "  (fr) Chirpy Cheep Cheep
      "  (fr) Taylor Swallow


    Company of Friends (empl-of) Robo1 
             "         (empl-of) Robo2
             "         (empl-of) Bot1
             "         (empl-of) Bot2
             "         (empl-of) Bot3
             "         (empl-of) Bot4
             "         (empl-of) Rob1Bot21

``` julia
store4 = MemoryStore()
try
    cr4 = compile_n4l_string!(store4, friends_text; config_dir=SST_CONFIG)
    println("Nodes: $(cr4.nodes_created), Edges: $(cr4.edges_created)")
catch e
    println("Compilation note: ", e)
end

println("Graph: $(node_count(store4)) nodes, $(link_count(store4)) links")
```

    Nodes: 36, Edges: 39
    Graph: 36 nodes, 78 links

Analyse the social network structure:

``` julia
adj4 = SemanticSpacetime.AdjacencyMatrix()
for (nptr, node) in store4.nodes
    for links in node.incidence
        for link in links
            SemanticSpacetime.add_edge!(adj4, nptr, link.dst, Float64(link.wgt))
        end
    end
end

println(graph_summary(adj4))
```

    Graph Summary
    ─────────────
      Nodes:   36
      Links:   76 (directed)
      Sources: 0
      Sinks:   0
      Top centrality:
        (1,1)  1.0000
        (1,9)  0.7829
        (1,12)  0.2828
        (1,19)  0.2696
        (1,4)  0.2364

``` julia
# Find the most connected individuals
if !isempty(adj4.nodes)
    centrality4 = eigenvector_centrality(adj4; max_iter=100, tol=1e-6)
    ranked4 = sort(collect(centrality4), by=x -> x.second, rev=true)
    println("Most central people in the network:")
    for (nptr, score) in ranked4[1:min(10, length(ranked4))]
        node = mem_get_node(store4, nptr)
        if node !== nothing
            println("  $(rpad(node.s, 25)) $(round(score, digits=4))")
        end
    end
end
```

    Most central people in the network:
      Mark                      1.0
      Mike                      0.7829
      Matt                      0.2828
      Jan                       0.2696
      Brent                     0.2364
      Bjørn                     0.2364
      Kat                       0.2364
      Mandy                     0.2364
      Carol                     0.2364
      Zhao                      0.2364

Find sources and sinks in the social graph:

``` julia
sources = find_sources(adj4)
sinks = find_sinks(adj4)
println("Sources (only give, never receive): $(length(sources))")
for nptr in sources[1:min(5, length(sources))]
    node = mem_get_node(store4, nptr)
    if node !== nothing
        println("  '$(node.s)'")
    end
end

println("Sinks (only receive, never give): $(length(sinks))")
for nptr in sinks[1:min(5, length(sinks))]
    node = mem_get_node(store4, nptr)
    if node !== nothing
        println("  '$(node.s)'")
    end
end
```

    Sources (only give, never receive): 0
    Sinks (only receive, never give): 0

## Summary

Real-world N4L files demonstrate the full SST pipeline:

| Step    | Function                                               |
|---------|--------------------------------------------------------|
| Load    | `read(path, String)`                                   |
| Compile | `compile_n4l_string!(store, text; config_dir=...)`     |
| Explore | `forward_cone`, `find_paths`                           |
| Analyse | `eigenvector_centrality`, `find_sources`, `find_sinks` |

The N4L format handles poetry, physics models, and social networks with
the same lightweight syntax.
