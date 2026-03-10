# Building Knowledge Graphs
Simon Frost

## Introduction

A knowledge graph in Semantic Spacetime is more than a bag of triples —
it is a structured, typed representation of a domain organized by
*chapters* (topics) and *contexts* (tags). This vignette demonstrates
how to build a realistic knowledge graph modelling an infectious disease
system.

## Setup

``` julia
using SemanticSpacetime

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()

# Register a comprehensive set of arrows
# LEADSTO
then_f = insert_arrow!("LEADSTO", "then", "leads to", "+")
then_b = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
insert_inverse_arrow!(then_f, then_b)

causes_f = insert_arrow!("LEADSTO", "causes", "causes", "+")
causes_b = insert_arrow!("LEADSTO", "caused-by", "caused by", "-")
insert_inverse_arrow!(causes_f, causes_b)

affects_f = insert_arrow!("LEADSTO", "affects", "affects", "+")
affects_b = insert_arrow!("LEADSTO", "affected-by", "is affected by", "-")
insert_inverse_arrow!(affects_f, affects_b)

# CONTAINS
has_f = insert_arrow!("CONTAINS", "has", "contains", "+")
has_b = insert_arrow!("CONTAINS", "in", "is in", "-")
insert_inverse_arrow!(has_f, has_b)

part_f = insert_arrow!("CONTAINS", "has-part", "has part", "+")
part_b = insert_arrow!("CONTAINS", "part-of", "is part of", "-")
insert_inverse_arrow!(part_f, part_b)

# EXPRESS
note_arr = insert_arrow!("EXPRESS", "note", "has note", "+")
eg_arr = insert_arrow!("EXPRESS", "e.g.", "has example", "+")
name_arr = insert_arrow!("EXPRESS", "name", "has name", "+")

# NEAR
like_arr = insert_arrow!("NEAR", "like", "is similar to", "+")

store = MemoryStore()
```

    MemoryStore
      Nodes:    0
      Links:    0
      Chapters: 

## Chapters as Topic Boundaries

Chapters organize the graph into thematic sections. A node belongs to
exactly one chapter, but edges can cross chapter boundaries. Think of
chapters as sections in a notebook.

``` julia
# Chapter: pathogen — describe the virus
virus = mem_vertex!(store, "SARS-CoV-2", "pathogen")
spike = mem_vertex!(store, "spike protein", "pathogen")
rna = mem_vertex!(store, "RNA genome", "pathogen")
mem_edge!(store, virus, "has-part", spike)
mem_edge!(store, virus, "has-part", rna)
mem_edge!(store, virus, "name", mem_vertex!(store, "severe acute respiratory syndrome coronavirus 2", "pathogen"))

# Chapter: transmission — how the disease spreads
droplets = mem_vertex!(store, "respiratory droplets", "transmission")
aerosol = mem_vertex!(store, "aerosol transmission", "transmission")
contact = mem_vertex!(store, "close contact", "transmission")
mem_edge!(store, contact, "causes", mem_vertex!(store, "exposure", "transmission"), ["airborne"])
mem_edge!(store, droplets, "like", aerosol)

# Chapter: disease — clinical progression
infection = mem_vertex!(store, "infection", "disease")
incubation = mem_vertex!(store, "incubation period", "disease")
symptoms = mem_vertex!(store, "symptom onset", "disease")
fever = mem_vertex!(store, "fever", "disease")
cough = mem_vertex!(store, "cough", "disease")
recovery = mem_vertex!(store, "recovery", "disease")
severe = mem_vertex!(store, "severe disease", "disease")

# Temporal chain of disease progression
mem_edge!(store, infection, "then", incubation)
mem_edge!(store, incubation, "then", symptoms)
mem_edge!(store, symptoms, "then", recovery)
mem_edge!(store, symptoms, "then", severe)

# Symptoms as parts of the disease
mem_edge!(store, symptoms, "has", fever)
mem_edge!(store, symptoms, "has", cough)

# Chapter: intervention — public health responses
vaccine = mem_vertex!(store, "mRNA vaccine", "intervention")
mask = mem_vertex!(store, "face mask", "intervention")
distancing = mem_vertex!(store, "social distancing", "intervention")

println("Graph: $(node_count(store)) nodes, $(link_count(store)) links")
println("Chapters: ", join(mem_get_chapters(store), ", "))
```

    Graph: 18 nodes, 20 links
    Chapters: disease, intervention, pathogen, transmission

## Cross-Chapter Edges

Edges can link nodes across chapters, capturing how different aspects of
a domain interact:

``` julia
# The virus causes infection (pathogen → disease)
mem_edge!(store, virus, "causes", infection, ["epidemiology"])

# Spike protein enables transmission (pathogen → transmission)
mem_edge!(store, spike, "causes", mem_vertex!(store, "cell entry", "transmission"), ["mechanism"])

# Vaccines affect the virus (intervention → pathogen)
mem_edge!(store, vaccine, "affects", spike, ["immunology"])

# Masks reduce transmission (intervention → transmission)
mem_edge!(store, mask, "affects", droplets, ["prevention"])
mem_edge!(store, distancing, "affects", contact, ["prevention"])

println("Cross-chapter links created")
println("Updated: $(node_count(store)) nodes, $(link_count(store)) links")
```

    Cross-chapter links created
    Updated: 19 nodes, 30 links

## Using Contexts

Contexts are metadata tags attached to edges that describe *the
perspective* or *domain* of a relationship. They enable filtered views
of the same graph.

``` julia
# Add nodes with contextual edges
r0 = mem_vertex!(store, "basic reproduction number", "epidemiology")
mem_edge!(store, r0, "note",
          mem_vertex!(store, "R0 ≈ 2-3 for original strain", "epidemiology"),
          ["statistics", "modelling"])

mem_edge!(store, r0, "note",
          mem_vertex!(store, "R0 influenced by contact patterns", "epidemiology"),
          ["behaviour", "modelling"])

mem_edge!(store, r0, "affects", severe,
          ["public-health", "modelling"])

println("Contextual edges added")
```

    Contextual edges added

## Idempotent Operations

A key feature of SST is that `mem_vertex!` is *idempotent* — adding the
same node twice returns the existing one. This simplifies graph
construction since you don’t need to track whether a node already
exists.

``` julia
v1 = mem_vertex!(store, "SARS-CoV-2", "pathogen")
v2 = mem_vertex!(store, "SARS-CoV-2", "pathogen")
println("Same node? $(v1.nptr == v2.nptr)")
println("Node count unchanged: $(node_count(store))")
```

    Same node? true
    Node count unchanged: 22

## Inspecting the Graph

Let’s examine the structure we’ve built:

``` julia
# Show node distribution across chapters
for chap in sort(mem_get_chapters(store))
    count = 0
    for (_, node) in store.nodes
        if node.chap == chap
            count += 1
        end
    end
    println("  $chap: $count nodes")
end
```

      disease: 7 nodes
      epidemiology: 3 nodes
      intervention: 3 nodes
      pathogen: 4 nodes
      transmission: 5 nodes

``` julia
# Show the incidence structure of the virus node
channel_names = ["-EXPRESS", "-CONTAINS", "-LEADSTO", "NEAR",
                 "+LEADSTO", "+CONTAINS", "+EXPRESS"]

println("Links from 'SARS-CoV-2':")
for (i, links) in enumerate(virus.incidence)
    for link in links
        dst = mem_get_node(store, link.dst)
        arr = get_arrow_by_ptr(link.arr)
        if dst !== nothing
            println("  [$(channel_names[i])] —($(arr.short))→ '$(dst.s)'")
        end
    end
end
```

    Links from 'SARS-CoV-2':
      [+LEADSTO] —(causes)→ 'infection'
      [+CONTAINS] —(has-part)→ 'spike protein'
      [+CONTAINS] —(has-part)→ 'RNA genome'
      [+EXPRESS] —(name)→ 'severe acute respiratory syndrome coronavirus 2'

## Building with Annotations

EXPRESS edges are particularly useful for adding metadata, examples, and
notes to any node:

``` julia
# Annotate the vaccine node
mem_edge!(store, vaccine, "note",
          mem_vertex!(store, "Pfizer-BioNTech BNT162b2", "intervention"))
mem_edge!(store, vaccine, "note",
          mem_vertex!(store, "Moderna mRNA-1273", "intervention"))
mem_edge!(store, vaccine, "e.g.",
          mem_vertex!(store, "two-dose regimen with 21-day interval", "intervention"))

println("Final graph: $(node_count(store)) nodes, $(link_count(store)) links")
```

    Final graph: 25 nodes, 37 links

## Summary

Key patterns for building SST knowledge graphs:

1.  **Organize by chapter** — group related nodes into thematic sections
2.  **Use typed arrows** — choose the right STType for each relationship
3.  **Add context** — tag edges with topic keywords for filtered views
4.  **Cross-reference** — connect nodes across chapters to capture
    cross-domain relationships
5.  **Annotate freely** — use EXPRESS edges for notes, examples, and
    metadata
