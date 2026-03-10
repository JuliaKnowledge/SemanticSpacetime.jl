# RDF Integration
Simon Frost

## Introduction

While Semantic Spacetime has a richer type system than RDF (Resource
Description Framework), interoperability with the Semantic Web is
valuable. SemanticSpacetime.jl can convert SST graphs to and from RDF
triples, and serialise/deserialise in Turtle format. This vignette shows
how to bridge the two worlds.

## Setup

``` julia
using SemanticSpacetime

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()

# Register arrows
then_f = insert_arrow!("LEADSTO", "then", "leads to", "+")
then_b = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
insert_inverse_arrow!(then_f, then_b)

has_f = insert_arrow!("CONTAINS", "has", "contains", "+")
has_b = insert_arrow!("CONTAINS", "in", "is in", "-")
insert_inverse_arrow!(has_f, has_b)

note_arr = insert_arrow!("EXPRESS", "note", "has note", "+")
eg_arr = insert_arrow!("EXPRESS", "e.g.", "has example", "+")
like_arr = insert_arrow!("NEAR", "like", "is similar to", "+")
```

    7

## Building an SST Graph

Let’s create a small astronomy knowledge graph:

``` julia
store = MemoryStore()

# Solar system structure
solar = mem_vertex!(store, "Solar System", "astronomy")
sun = mem_vertex!(store, "Sun", "astronomy")
earth = mem_vertex!(store, "Earth", "astronomy")
mars = mem_vertex!(store, "Mars", "astronomy")
jupiter = mem_vertex!(store, "Jupiter", "astronomy")

mem_edge!(store, solar, "has", sun)
mem_edge!(store, solar, "has", earth)
mem_edge!(store, solar, "has", mars)
mem_edge!(store, solar, "has", jupiter)

# Properties
mem_edge!(store, earth, "note", mem_vertex!(store, "third planet from the Sun", "astronomy"))
mem_edge!(store, mars, "note", mem_vertex!(store, "the red planet", "astronomy"))
mem_edge!(store, jupiter, "note", mem_vertex!(store, "largest planet", "astronomy"))

# Similarity
mem_edge!(store, earth, "like", mars, ["rocky-planets"])

# Process
mem_edge!(store, sun, "then", mem_vertex!(store, "solar wind", "astronomy"))

println("SST graph: $(node_count(store)) nodes, $(link_count(store)) links")
```

    SST graph: 9 nodes, 14 links

## SST Namespaces

RDF requires URIs for subjects, predicates, and objects. SST uses a
namespace configuration to generate these:

``` julia
# Default namespace
ns = sst_namespace()
println("Base URI: $(ns.base)")
println("Vocab URI: $(ns.vocab)")
```

    Base URI: http://sst.example.org/
    Vocab URI: http://sst.example.org/vocab#

``` julia
# Custom namespace for a project
ns_astro = sst_namespace("http://astronomy.example.org/kg/")
println("Custom base: $(ns_astro.base)")
```

    Custom base: http://astronomy.example.org/kg/

## Converting SST to RDF Triples

The `sst_to_rdf` function converts the entire SST graph into a list of
RDF triples:

``` julia
triples = sst_to_rdf(store; namespace=ns_astro)
println("Generated $(length(triples)) RDF triples\n")

for t in triples[1:min(10, length(triples))]
    println("  $(t.subject)")
    println("    $(t.predicate)")
    println("    $(t.object)")
    println()
end
```

    Generated 70 RDF triples

      http://astronomy.example.org/kg/node/solar_wind
        http://www.w3.org/1999/02/22-rdf-syntax-ns#type
        http://astronomy.example.org/kg/vocab#Node

      http://astronomy.example.org/kg/node/solar_wind
        http://www.w3.org/2000/01/rdf-schema#label
        solar wind

      http://astronomy.example.org/kg/node/solar_wind
        http://astronomy.example.org/kg/vocab#chapter
        http://astronomy.example.org/kg/chapter/astronomy

      http://astronomy.example.org/kg/node/Solar_System
        http://www.w3.org/1999/02/22-rdf-syntax-ns#type
        http://astronomy.example.org/kg/vocab#Node

      http://astronomy.example.org/kg/node/Solar_System
        http://www.w3.org/2000/01/rdf-schema#label
        Solar System

      http://astronomy.example.org/kg/node/Solar_System
        http://astronomy.example.org/kg/vocab#chapter
        http://astronomy.example.org/kg/chapter/astronomy

      http://astronomy.example.org/kg/node/Mars
        http://www.w3.org/1999/02/22-rdf-syntax-ns#type
        http://astronomy.example.org/kg/vocab#Node

      http://astronomy.example.org/kg/node/Mars
        http://www.w3.org/2000/01/rdf-schema#label
        Mars

      http://astronomy.example.org/kg/node/Mars
        http://astronomy.example.org/kg/vocab#chapter
        http://astronomy.example.org/kg/chapter/astronomy

      http://astronomy.example.org/kg/node/Sun
        http://www.w3.org/1999/02/22-rdf-syntax-ns#type
        http://astronomy.example.org/kg/vocab#Node

## Exporting as Turtle

Turtle is a compact, human-readable RDF serialisation format. SST graphs
can be exported directly:

``` julia
turtle = export_turtle(store; namespace=ns_astro)
println(turtle)
```

    @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
    @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
    @prefix sst: <http://astronomy.example.org/kg/> .
    @prefix sst-vocab: <http://astronomy.example.org/kg/vocab#> .

    <http://astronomy.example.org/kg/node/solar_wind> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#Node> .
    <http://astronomy.example.org/kg/node/solar_wind> <http://www.w3.org/2000/01/rdf-schema#label> "solar wind" .
    <http://astronomy.example.org/kg/node/solar_wind> <http://astronomy.example.org/kg/vocab#chapter> <http://astronomy.example.org/kg/chapter/astronomy> .
    <http://astronomy.example.org/kg/node/Solar_System> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#Node> .
    <http://astronomy.example.org/kg/node/Solar_System> <http://www.w3.org/2000/01/rdf-schema#label> "Solar System" .
    <http://astronomy.example.org/kg/node/Solar_System> <http://astronomy.example.org/kg/vocab#chapter> <http://astronomy.example.org/kg/chapter/astronomy> .
    <http://astronomy.example.org/kg/node/Mars> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#Node> .
    <http://astronomy.example.org/kg/node/Mars> <http://www.w3.org/2000/01/rdf-schema#label> "Mars" .
    <http://astronomy.example.org/kg/node/Mars> <http://astronomy.example.org/kg/vocab#chapter> <http://astronomy.example.org/kg/chapter/astronomy> .
    <http://astronomy.example.org/kg/node/Sun> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#Node> .
    <http://astronomy.example.org/kg/node/Sun> <http://www.w3.org/2000/01/rdf-schema#label> "Sun" .
    <http://astronomy.example.org/kg/node/Sun> <http://astronomy.example.org/kg/vocab#chapter> <http://astronomy.example.org/kg/chapter/astronomy> .
    <http://astronomy.example.org/kg/node/Jupiter> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#Node> .
    <http://astronomy.example.org/kg/node/Jupiter> <http://www.w3.org/2000/01/rdf-schema#label> "Jupiter" .
    <http://astronomy.example.org/kg/node/Jupiter> <http://astronomy.example.org/kg/vocab#chapter> <http://astronomy.example.org/kg/chapter/astronomy> .
    <http://astronomy.example.org/kg/node/the_red_planet> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#Node> .
    <http://astronomy.example.org/kg/node/the_red_planet> <http://www.w3.org/2000/01/rdf-schema#label> "the red planet" .
    <http://astronomy.example.org/kg/node/the_red_planet> <http://astronomy.example.org/kg/vocab#chapter> <http://astronomy.example.org/kg/chapter/astronomy> .
    <http://astronomy.example.org/kg/node/largest_planet> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#Node> .
    <http://astronomy.example.org/kg/node/largest_planet> <http://www.w3.org/2000/01/rdf-schema#label> "largest planet" .
    <http://astronomy.example.org/kg/node/largest_planet> <http://astronomy.example.org/kg/vocab#chapter> <http://astronomy.example.org/kg/chapter/astronomy> .
    <http://astronomy.example.org/kg/node/Earth> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#Node> .
    <http://astronomy.example.org/kg/node/Earth> <http://www.w3.org/2000/01/rdf-schema#label> "Earth" .
    <http://astronomy.example.org/kg/node/Earth> <http://astronomy.example.org/kg/vocab#chapter> <http://astronomy.example.org/kg/chapter/astronomy> .
    <http://astronomy.example.org/kg/node/third_planet_from_the_Sun> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#Node> .
    <http://astronomy.example.org/kg/node/third_planet_from_the_Sun> <http://www.w3.org/2000/01/rdf-schema#label> "third planet from the Sun" .
    <http://astronomy.example.org/kg/node/third_planet_from_the_Sun> <http://astronomy.example.org/kg/vocab#chapter> <http://astronomy.example.org/kg/chapter/astronomy> .
    <http://astronomy.example.org/kg/node/solar_wind> <http://astronomy.example.org/kg/vocab#prev> <http://astronomy.example.org/kg/node/Sun> .
    <http://astronomy.example.org/kg/vocab#prev> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#prev> <http://www.w3.org/2000/01/rdf-schema#label> "-LEADSTO" .
    <http://astronomy.example.org/kg/node/Solar_System> <http://astronomy.example.org/kg/vocab#has> <http://astronomy.example.org/kg/node/Sun> .
    <http://astronomy.example.org/kg/vocab#has> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#has> <http://www.w3.org/2000/01/rdf-schema#label> "+CONTAINS" .
    <http://astronomy.example.org/kg/node/Solar_System> <http://astronomy.example.org/kg/vocab#has> <http://astronomy.example.org/kg/node/Earth> .
    <http://astronomy.example.org/kg/vocab#has> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#has> <http://www.w3.org/2000/01/rdf-schema#label> "+CONTAINS" .
    <http://astronomy.example.org/kg/node/Solar_System> <http://astronomy.example.org/kg/vocab#has> <http://astronomy.example.org/kg/node/Mars> .
    <http://astronomy.example.org/kg/vocab#has> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#has> <http://www.w3.org/2000/01/rdf-schema#label> "+CONTAINS" .
    <http://astronomy.example.org/kg/node/Solar_System> <http://astronomy.example.org/kg/vocab#has> <http://astronomy.example.org/kg/node/Jupiter> .
    <http://astronomy.example.org/kg/vocab#has> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#has> <http://www.w3.org/2000/01/rdf-schema#label> "+CONTAINS" .
    <http://astronomy.example.org/kg/node/Mars> <http://astronomy.example.org/kg/vocab#in> <http://astronomy.example.org/kg/node/Solar_System> .
    <http://astronomy.example.org/kg/vocab#in> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#in> <http://www.w3.org/2000/01/rdf-schema#label> "-CONTAINS" .
    <http://astronomy.example.org/kg/node/Mars> <http://astronomy.example.org/kg/vocab#note> <http://astronomy.example.org/kg/node/the_red_planet> .
    <http://astronomy.example.org/kg/vocab#note> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#note> <http://www.w3.org/2000/01/rdf-schema#label> "+EXPRESS" .
    <http://astronomy.example.org/kg/node/Sun> <http://astronomy.example.org/kg/vocab#in> <http://astronomy.example.org/kg/node/Solar_System> .
    <http://astronomy.example.org/kg/vocab#in> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#in> <http://www.w3.org/2000/01/rdf-schema#label> "-CONTAINS" .
    <http://astronomy.example.org/kg/node/Sun> <http://astronomy.example.org/kg/vocab#then> <http://astronomy.example.org/kg/node/solar_wind> .
    <http://astronomy.example.org/kg/vocab#then> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#then> <http://www.w3.org/2000/01/rdf-schema#label> "+LEADSTO" .
    <http://astronomy.example.org/kg/node/Jupiter> <http://astronomy.example.org/kg/vocab#in> <http://astronomy.example.org/kg/node/Solar_System> .
    <http://astronomy.example.org/kg/vocab#in> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#in> <http://www.w3.org/2000/01/rdf-schema#label> "-CONTAINS" .
    <http://astronomy.example.org/kg/node/Jupiter> <http://astronomy.example.org/kg/vocab#note> <http://astronomy.example.org/kg/node/largest_planet> .
    <http://astronomy.example.org/kg/vocab#note> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#note> <http://www.w3.org/2000/01/rdf-schema#label> "+EXPRESS" .
    <http://astronomy.example.org/kg/node/Earth> <http://astronomy.example.org/kg/vocab#in> <http://astronomy.example.org/kg/node/Solar_System> .
    <http://astronomy.example.org/kg/vocab#in> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#in> <http://www.w3.org/2000/01/rdf-schema#label> "-CONTAINS" .
    <http://astronomy.example.org/kg/node/Earth> <http://astronomy.example.org/kg/vocab#like> <http://astronomy.example.org/kg/node/Mars> .
    <http://astronomy.example.org/kg/vocab#like> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#like> <http://www.w3.org/2000/01/rdf-schema#label> "NEAR" .
    <http://astronomy.example.org/kg/node/Earth> <http://astronomy.example.org/kg/vocab#context> <http://astronomy.example.org/kg/context/rocky-planets> .
    <http://astronomy.example.org/kg/node/Earth> <http://astronomy.example.org/kg/vocab#note> <http://astronomy.example.org/kg/node/third_planet_from_the_Sun> .
    <http://astronomy.example.org/kg/vocab#note> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://astronomy.example.org/kg/vocab#STType> .
    <http://astronomy.example.org/kg/vocab#note> <http://www.w3.org/2000/01/rdf-schema#label> "+EXPRESS" .

## Importing Turtle into SST

You can also go the other direction — import RDF Turtle data into an SST
graph. This is useful for integrating external Linked Data sources.

``` julia
# Create Turtle data about constellations
turtle_input = """
@prefix sst: <http://astronomy.example.org/kg/> .
@prefix sstp: <http://astronomy.example.org/kg/vocab/> .

sst:Orion sstp:contains sst:Betelgeuse .
sst:Orion sstp:contains sst:Rigel .
sst:Orion sstp:note "winter constellation" .
sst:UrsaMajor sstp:contains sst:Polaris .
"""

import_store = MemoryStore()
import_turtle!(import_store, turtle_input; namespace=ns_astro, chapter="constellations")

println("Imported: $(node_count(import_store)) nodes, $(link_count(import_store)) links")
```

    Imported: 6 nodes, 7 links

``` julia
# Check what was imported
for name in ["Orion", "Betelgeuse", "Rigel", "UrsaMajor", "Polaris"]
    nodes = mem_get_nodes_by_name(import_store, name)
    if !isempty(nodes)
        println("Found: '$(nodes[1].s)' in chapter '$(nodes[1].chap)'")
    end
end
```

    Found: 'Orion' in chapter 'constellations'
    Found: 'Betelgeuse' in chapter 'constellations'
    Found: 'Rigel' in chapter 'constellations'
    Found: 'UrsaMajor' in chapter 'constellations'
    Found: 'Polaris' in chapter 'constellations'

## Round-Trip Conversion

A key test of any serialisation format is the round trip — can you
export and re-import without losing information?

``` julia
# Export the original store
turtle_out = export_turtle(store; namespace=ns_astro)

# Import into a fresh store
round_trip_store = MemoryStore()
import_turtle!(round_trip_store, turtle_out; namespace=ns_astro, chapter="astronomy")

println("Original: $(node_count(store)) nodes, $(link_count(store)) links")
println("Round-trip: $(node_count(round_trip_store)) nodes, $(link_count(round_trip_store)) links")
```

    Original: 9 nodes, 14 links
    Round-trip: 9 nodes, 14 links

## Parsing Raw Turtle

The `parse_turtle` function converts Turtle text into a vector of
`RDFTriple` structs without loading them into a store:

``` julia
raw_triples = parse_turtle("""
@prefix ex: <http://example.org/> .
ex:Alice ex:knows ex:Bob .
ex:Bob ex:knows ex:Carol .
ex:Carol ex:knows ex:Alice .
""")

println("Parsed $(length(raw_triples)) triples:")
for t in raw_triples
    println("  $(t.subject) —[$(t.predicate)]→ $(t.object)")
end
```

    Parsed 3 triples:
      http://example.org/Alice —[http://example.org/knows]→ http://example.org/Bob
      http://example.org/Bob —[http://example.org/knows]→ http://example.org/Carol
      http://example.org/Carol —[http://example.org/knows]→ http://example.org/Alice

## Converting Triples to SST

You can also convert a vector of `RDFTriple` structs directly into an
SST store using `rdf_to_sst!`:

``` julia
triple_store = MemoryStore()
rdf_to_sst!(triple_store, raw_triples; namespace=sst_namespace("http://example.org/"), chapter="social")

println("Converted: $(node_count(triple_store)) nodes, $(link_count(triple_store)) links")
```

    Converted: 3 nodes, 3 links

## SST vs RDF: What’s Different?

SST’s type system is strictly richer than RDF’s:

| Feature | RDF | SST |
|----|----|----|
| Edge types | Arbitrary predicates | 4 STTypes × 2 directions = 7 channels |
| Node classification | Via `rdf:type` triples | Built-in ETC (Event/Thing/Concept) |
| Causality | No built-in notion | LEADSTO type with cone search |
| Containment | No built-in notion | CONTAINS type with hierarchy |
| Context | Named graphs | Per-edge context tags |
| Chapters | No equivalent | Built-in topic grouping |

When converting SST → RDF, some semantic richness is flattened into
predicates. When converting RDF → SST, predicates are mapped to the
closest STType. The `PredicateMapping` system allows you to customise
this mapping for domain-specific vocabularies.

## Summary

SemanticSpacetime.jl provides full bidirectional RDF integration:

| Function         | Purpose                             |
|------------------|-------------------------------------|
| `sst_to_rdf`     | Convert SST graph → RDF triples     |
| `rdf_to_sst!`    | Convert RDF triples → SST graph     |
| `export_turtle`  | Serialise SST graph as Turtle       |
| `import_turtle!` | Parse Turtle text into SST graph    |
| `parse_turtle`   | Parse Turtle into RDFTriple structs |
| `sst_namespace`  | Configure URI namespace             |

This enables SST to participate in the broader Linked Data ecosystem
while retaining its richer spacetime type semantics internally.
