# The N4L Language
Simon Frost

## Introduction

N4L (Notes for Learning) is a lightweight, human-readable markup
language for building SST knowledge graphs. Instead of writing
programmatic `mem_vertex!` and `mem_edge!` calls, you can describe your
knowledge in a natural text format and have it compiled into a graph
automatically.

N4L was designed to be as close to free-form note-taking as possible,
while being parseable into a structured graph.

## Setup

``` julia
using SemanticSpacetime

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()

# Point to the SSTorytime config directory for full arrow definitions
const SST_CONFIG = joinpath(@__DIR__, "..", "..", "..", "SSTorytime", "SSTconfig")
println("Config available: ", isdir(SST_CONFIG))
```

    Config available: true

## N4L Basics

An N4L document consists of **sections** (chapters), **items** (nodes),
and **relations** (edges). Here is a minimal example:

``` julia
n4l_text = """
-planets

 Earth
 Mars
 Jupiter
 Saturn
"""

result = parse_n4l(n4l_text; config_dir=SST_CONFIG)
println("Errors: ", length(result.errors))
println("Warnings: ", length(result.warnings))
```

    Errors: 0
    Warnings: 0

The `-planets` line creates a section (chapter) called “planets”. Each
indented line becomes a node in that chapter.

## Compiling N4L into a Graph

Once parsed, we compile the result into a `MemoryStore`:

``` julia
store = MemoryStore()
cr = compile_n4l!(store, result)

println("Nodes created: $(cr.nodes_created)")
println("Edges created: $(cr.edges_created)")
println("Chapters: ", join(cr.chapters, ", "))
```

    Nodes created: 4
    Edges created: 0
    Chapters: planets

``` julia
# Verify the nodes exist
for name in ["Earth", "Mars", "Jupiter", "Saturn"]
    nodes = mem_get_nodes_by_name(store, name)
    if !isempty(nodes)
        println("Found: '$(nodes[1].s)' in chapter '$(nodes[1].chap)'")
    end
end
```

    Found: 'Earth' in chapter 'planets'
    Found: 'Mars' in chapter 'planets'
    Found: 'Jupiter' in chapter 'planets'
    Found: 'Saturn' in chapter 'planets'

## Relations (Edges)

N4L expresses relationships by placing an arrow name in parentheses
between two items:

``` julia
n4l_relations = """
-solar system

 Sun (contain) Earth
 Sun (contain) Mars
 Sun (contain) Jupiter
 Earth (contain) Moon
 Mars (contain) Phobos
 Mars (contain) Deimos
 Jupiter (contain) Europa
 Jupiter (contain) Ganymede
"""

store2 = MemoryStore()
cr2 = compile_n4l_string!(store2, n4l_relations; config_dir=SST_CONFIG)

println("Nodes: $(cr2.nodes_created), Edges: $(cr2.edges_created)")
```

    Nodes: 9, Edges: 8

## Chaining Relations

You can chain multiple relations on a single line:

``` julia
n4l_chain = """
-process

 wake up (then) eat breakfast (then) go to work (then) come home
"""

store3 = MemoryStore()
cr3 = compile_n4l_string!(store3, n4l_chain; config_dir=SST_CONFIG)

println("Nodes: $(cr3.nodes_created), Edges: $(cr3.edges_created)")
```

    Nodes: 4, Edges: 3

This creates a chain: wake up → eat breakfast → go to work → come home,
with three LEADSTO edges.

## Contexts

Contexts are metadata tags that apply to subsequent items and edges.
They are enclosed in colons:

``` julia
n4l_context = """
-geography

 : europe, countries :

 France (contain) Paris
 Germany (contain) Berlin
 Spain (contain) Madrid

 : asia, countries :

 Japan (contain) Tokyo
 China (contain) Beijing
"""

store4 = MemoryStore()
cr4 = compile_n4l_string!(store4, n4l_context; config_dir=SST_CONFIG)

println("Nodes: $(cr4.nodes_created), Edges: $(cr4.edges_created)")
```

    Nodes: 10, Edges: 5

Contexts persist until a new context block is encountered. This lets you
tag sections of your notes with topics.

## Annotations with EXPRESS Arrows

The `(note)` and `(e.g.)` arrows create EXPRESS edges — perfect for
adding commentary:

``` julia
n4l_notes = """
-programming

 Python (note) interpreted language
 Python (e.g.) data science scripting
 Julia (note) just-in-time compiled
 Julia (e.g.) scientific computing
 Python (sim) Julia
"""

store5 = MemoryStore()
cr5 = compile_n4l_string!(store5, n4l_notes; config_dir=SST_CONFIG)

println("Nodes: $(cr5.nodes_created), Edges: $(cr5.edges_created)")
```

    Nodes: 6, Edges: 6

## Multiple Sections

An N4L document can contain multiple sections. Each `-name` line starts
a new chapter:

``` julia
n4l_multi = """
-animals

 Cat
 Dog
 Cat (sim) Dog

-plants

 Oak
 Rose
 Fern

-ecology

 Cat (fwd) Rose
 Dog (fwd) Oak
"""

store6 = MemoryStore()
cr6 = compile_n4l_string!(store6, n4l_multi; config_dir=SST_CONFIG)

println("Nodes: $(cr6.nodes_created), Edges: $(cr6.edges_created)")
println("Chapters: ", join(cr6.chapters, ", "))
```

    Nodes: 7, Edges: 4
    Chapters: animals

## The compile_n4l_string! Convenience Function

For quick experimentation, `compile_n4l_string!` combines parsing and
compilation in one step:

``` julia
store7 = MemoryStore()
cr7 = compile_n4l_string!(store7, """
-recipes

 flour (then) mix with water (then) knead dough (then) let rise (then) bake

 : ingredients :

 bread (contain) flour
 bread (contain) water
 bread (contain) yeast
 bread (contain) salt
"""; config_dir=SST_CONFIG)

println("Built recipe graph: $(cr7.nodes_created) nodes, $(cr7.edges_created) edges")

# Inspect the result
for name in ["flour", "bread", "bake"]
    nodes = mem_get_nodes_by_name(store7, name)
    if !isempty(nodes)
        n = nodes[1]
        total_links = sum(length(ch) for ch in n.incidence)
        println("'$(n.s)': $total_links connections")
    end
end
```

    Built recipe graph: 9 nodes, 8 edges
    'flour': 2 connections
    'bread': 4 connections
    'bake': 1 connections

## Validation

You can validate N4L text without compiling it using `validate_n4l`:

``` julia
vr = validate_n4l("-test\n\n good item\n another item\n"; config_dir=SST_CONFIG)
println("Valid: ", vr.valid)
println("Errors: ", length(vr.errors))
println("Warnings: ", length(vr.warnings))
```

    Valid: true
    Errors: 0
    Warnings: 0

## N4L Syntax Summary

| Syntax                | Meaning                          |
|-----------------------|----------------------------------|
| `-section name`       | Start a new chapter/section      |
| `item text`           | Create a node (indented)         |
| `A (arrow) B`         | Create an edge from A to B       |
| `A (arr1) B (arr2) C` | Chain: A→B and B→C               |
| `: tag1, tag2 :`      | Set context for subsequent items |
| `# comment`           | Comment line (ignored)           |
| `// comment`          | Alternative comment syntax       |

## Summary

N4L provides a lightweight, readable syntax for building SST knowledge
graphs. It maps directly onto the SST model: sections become chapters,
items become nodes, and parenthesised arrows become typed edges. For
large knowledge bases, N4L files are far more maintainable than
programmatic graph construction.
