# Knowledge Graphs from Structured Data
Simon Frost

## Introduction

SST can represent structured data — such as music catalogues,
inventories, or databases — as typed knowledge graphs. This vignette
loads the `MusicCollection/example_collection.n4l` example, which
encodes a collection of Rush and Vaughan Williams albums with tracks,
durations, composers, and producers. It uses its own custom `SSTconfig`
with domain-specific arrow types.

## Setup

``` julia
using SemanticSpacetime

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()

const MUSIC_DIR = joinpath(@__DIR__, "..", "..", "..", "SSTorytime", "examples", "MusicCollection")
const MUSIC_CONFIG = joinpath(MUSIC_DIR, "SSTconfig")
println("Music config available: ", isdir(MUSIC_CONFIG))
println("N4L file exists: ", isfile(joinpath(MUSIC_DIR, "example_collection.n4l")))
```

    Music config available: true
    N4L file exists: true

## Loading the Music Collection

The `example_collection.n4l` file uses domain-specific arrows like
`(album by)`, `(track in)`, `(duration)`, `(music by)`, and `(genre)`
defined in its own SSTconfig:

``` julia
music_text = read(joinpath(MUSIC_DIR, "example_collection.n4l"), String)
println("File size: $(length(music_text)) characters")
println("First 30 lines:")
for (i, line) in enumerate(split(music_text, '\n'))
    i > 30 && break
    println("  ", line)
end
```

    File size: 18110 characters
    First 30 lines:
      
      -music collection template
      
        :: rush albums, progressive rock ::
      
      @al_1 2112 (album by) Rush
              "  (tracks) 6
              "  (img) "/Resources/Rush/2112\ Delux\ Edition/folder.jpg"
              "  (released) March 1976
              "  (remastered) 2012
              "  (publisher) Mercury Records
              "  (genre) Progressive Rock  // Separate to make direct connection
              "  (genre) Concept Album
              "  (ensemble) electric rock band
              "  (music by) %"Alex Lifeson", %"Geddy Lee", %"Neil Peart"
              "  (words by) "Neil Peart"
              "  (producer) Terry Brown
              "  (next album) Farewell To Kings
      
       +:: _sequence_ ::
      
       1. 2112                   (track in) 2112
            "                    (duration) 20:33
      
       2. A Passage To Bangkok   (track in) 2112
            "                    (duration) 3:35
      
       3. The Twilight Zone      (track in) 2112
            "                    (duration) 3:20
      

``` julia
store = MemoryStore()
try
    cr = compile_n4l_string!(store, music_text; config_dir=MUSIC_CONFIG)
    println("Nodes: $(cr.nodes_created), Edges: $(cr.edges_created)")
    println("Chapters: ", join(cr.chapters, ", "))
catch e
    println("Compilation note: ", e)
end

println("\nGraph: $(node_count(store)) nodes, $(link_count(store)) links")
```

    Nodes: 194, Edges: 298
    Chapters: music collection template

    Graph: 194 nodes, 594 links

## Exploring the Structure

See how structured data (albums, artists, tracks) maps to SST nodes:

``` julia
# Look for album nodes
for album_name in ["2112", "Farewell To Kings", "Hemispheres"]
    nodes = mem_get_nodes_by_name(store, album_name)
    if !isempty(nodes)
        n = nodes[1]
        total_links = sum(length(ch) for ch in n.incidence)
        println("Album '$(n.s)' in chapter '$(n.chap)': $total_links connections")
    else
        println("Album '$album_name': not found by exact name")
    end
end
```

    Album '2112' in chapter 'music collection template': 20 connections
    Album 'Farewell To Kings' in chapter 'music collection template': 22 connections
    Album 'Hemispheres' in chapter 'music collection template': 18 connections

``` julia
# Search for artist-related nodes
for query in ["Rush", "Vaughan Williams", "Neil Peart"]
    results = mem_search_text(store, query)
    println("Search '$query': $(length(results)) results")
    for n in results[1:min(3, length(results))]
        label = first(split(n.s, '\n'))
        label = label[1:min(60, length(label))]
        println("  '$label' [$(n.chap)]")
    end
end
```

    Search 'Rush': 4 results
      'Rush' [music collection template]
      '/Resources/Rush/Hemispheres/folder.jpg' [music collection template]
      '/Resources/Rush/2112\ Delux\ Edition/folder.jpg' [music collection template]
    Search 'Vaughan Williams': 7 results
      'Ralph Vaughan Williams' [music collection template]
      'Andrew Manze & The Royal Liverpool Philharmonic Orchestra : ' [music collection template]
      'Vaughan Williams Symphony No.5 / Symphony No.6' [music collection template]
    Search 'Neil Peart': 2 results
      'Neil Peart' [music collection template]
      '"Alex Lifeson", "Geddy Lee", "Neil Peart"' [music collection template]

## Navigating Album→Track Relationships

Albums contain tracks via containment arrows. Let’s explore the album
structure:

``` julia
# Find tracks by searching for track-related text
tracks = mem_search_text(store, "track")
println("Track-related nodes: $(length(tracks))")
for t in tracks[1:min(5, length(tracks))]
    label = first(split(t.s, '\n'))  # first line only
    println("  '$(label[1:min(60, length(label))])'")
end
```

    Track-related nodes: 0

``` julia
# Search for specific songs (filter out multi-line nodes like lyrics)
for song in ["Passage To Bangkok", "Trees", "Twilight Zone", "Xanadu"]
    results = mem_search_text(store, song)
    # Filter to single-line, reasonably-sized titles
    titles = filter(n -> !occursin('\n', n.s) && length(n.s) < 80, results)
    if !isempty(titles)
        println("Found: '$(titles[1].s)'")
    elseif !isempty(results)
        println("Found: '$(first(split(results[1].s, '\n')))'  (multiline node)")
    end
end
```

    Found: '2. A Passage To Bangkok'
    Found: '3, The Trees'
    Found: '3. The Twilight Zone'
    Found: '2. Xanadu'

## Graph Statistics

``` julia
adj = SemanticSpacetime.AdjacencyMatrix()
for (nptr, node) in store.nodes
    for links in node.incidence
        for link in links
            SemanticSpacetime.add_edge!(adj, nptr, link.dst, Float64(link.wgt))
        end
    end
end

println(graph_summary(adj))
```

    Graph Summary
    ─────────────
      Nodes:   194
      Links:   590 (directed)
      Sources: 0
      Sinks:   0
      Top centrality:
        (3,3)  1.0000
        (1,1)  0.8137
        (1,12)  0.7526
        (4,1)  0.4012
        (2,7)  0.3890

## Centrality Analysis

Which nodes are most central in the music knowledge graph?

``` julia
if !isempty(adj.nodes)
    centrality = eigenvector_centrality(adj; max_iter=100, tol=1e-6)
    ranked = sort(collect(centrality), by=x -> x.second, rev=true)

    println("Most central nodes in the music collection:")
    for (nptr, score) in ranked[1:min(12, length(ranked))]
        node = mem_get_node(store, nptr)
        if node !== nothing
            label = first(split(node.s, '\n'))
            label = label[1:min(45, length(label))]
            println("  $(rpad(label, 47)) $(round(score, digits=4))")
        end
    end
end
```

    Most central nodes in the music collection:
      Farewell To Kings                               1.0
      2112                                            0.8137
      Hemispheres                                     0.7526
      "Alex Lifeson", "Geddy Lee", "Neil Peart"       0.4012
      Neil Peart                                      0.389
      Rush                                            0.3364
      Progressive Rock                                0.3364
      Concept Album                                   0.3364
      electric rock band                              0.3364
      Mercury Records                                 0.3364
      Terry Brown                                     0.3364
      6                                               0.2378

## Sources and Sinks

Sources are nodes with no incoming edges (e.g., top-level albums); sinks
are leaf nodes (e.g., duration values, producer names):

``` julia
sources = find_sources(adj)
println("Sources ($(length(sources))):")
for nptr in sources[1:min(8, length(sources))]
    node = mem_get_node(store, nptr)
    if node !== nothing
        println("  '$(first(split(node.s, '\n')))'")
    end
end

sinks = find_sinks(adj)
println("\nSinks ($(length(sinks))):")
for nptr in sinks[1:min(8, length(sinks))]
    node = mem_get_node(store, nptr)
    if node !== nothing
        println("  '$(first(split(node.s, '\n')))'")
    end
end
```

    Sources (0):

    Sinks (0):

## Cone Search from an Album

Trace what an album “contains” or “leads to”:

``` julia
# Find an album node and explore its cone
album_hits = mem_search_text(store, "2112")
if !isempty(album_hits)
    cone = forward_cone(store, album_hits[1].nptr; depth=3)
    println("Forward cone from '$(album_hits[1].s)':")
    for nptr in cone.supernodes
        node = mem_get_node(store, nptr)
        if node !== nothing
            println("  → '$(first(split(node.s, '\n')))'")
        end
    end
end
```

    Forward cone from '/Resources/Rush/2112\ Delux\ Edition/folder.jpg':

## Chapter Distribution

``` julia
chap_counts = Dict{String,Int}()
for (_, node) in store.nodes
    chap_counts[node.chap] = get(chap_counts, node.chap, 0) + 1
end

for (chap, count) in sort(collect(chap_counts), by=x -> -x.second)
    println("  $(rpad(chap, 30)) $count nodes")
end
```

      music collection template      194 nodes

## Summary

Structured data maps naturally to SST:

| Data Concept               | SST Representation           |
|----------------------------|------------------------------|
| Albums, Artists, Tracks    | Nodes in typed chapters      |
| “Album by Artist”          | LEADSTO or CONTAINS edges    |
| “Track in Album”           | CONTAINS edges (containment) |
| Metadata (duration, genre) | EXPRESS edges (properties)   |
| Similar artists            | NEAR edges (similarity)      |

The `MusicCollection` SSTconfig defines domain-specific arrows that make
the N4L notation expressive and natural for cataloguing structured data.
