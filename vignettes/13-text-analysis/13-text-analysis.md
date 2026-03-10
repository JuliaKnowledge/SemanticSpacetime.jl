# From Text to Knowledge
Simon Frost

## Introduction

SemanticSpacetime.jl can automatically extract knowledge structure from
plain text. The `text_to_n4l` function analyses text for intentionality
— identifying the most significant sentences — and formats them as N4L.
This vignette demonstrates the full text→N4L→graph→search pipeline.

## Setup

``` julia
using SemanticSpacetime

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()

const SST_CONFIG = joinpath(@__DIR__, "..", "..", "..", "SSTorytime", "SSTconfig")
println("Config available: ", isdir(SST_CONFIG))
```

    Config available: true

## Step 1: Text to N4L Conversion

Let’s start with a factual paragraph about climate science:

``` julia
factual_text = """
The global mean surface temperature has increased by approximately 1.1 degrees
Celsius since the pre-industrial era. This warming is primarily driven by
anthropogenic greenhouse gas emissions, particularly carbon dioxide from fossil
fuel combustion. The ocean has absorbed more than 90 percent of the excess heat,
leading to thermal expansion and contributing to sea level rise. Arctic sea ice
extent has declined significantly, with September minimums reaching record lows.
Climate models project continued warming under all emission scenarios, with
temperature increases ranging from 1.5 to 4.5 degrees by 2100. Extreme weather
events including heatwaves, droughts, and intense precipitation are becoming
more frequent and severe. Mitigation strategies focus on reducing emissions
through renewable energy adoption, energy efficiency improvements, and carbon
capture technologies. Adaptation measures include building resilient
infrastructure, developing drought-resistant crops, and implementing early
warning systems for extreme weather events.
"""

n4l_output = text_to_n4l(factual_text; chapter="climate science", target_percent=60.0)
println("--- Generated N4L ---")
println(n4l_output)
```

    --- Generated N4L ---
     - Samples from climate science

    # (begin) ************

     :: _sequence_ , climate science::

    @sen1   The global mean surface temperature has increased by approximately 1.1 degrees
                  " (extract-fr) part 0 of climate science

    @sen2   This warming is primarily driven by
                  " (extract-fr) part 0 of climate science

    @sen3   anthropogenic greenhouse gas emissions, particularly carbon dioxide from fossil
                  " (extract-fr) part 0 of climate science

    @sen4   The ocean has absorbed more than 90 percent of the excess heat,
                  " (extract-fr) part 0 of climate science

    @sen5   leading to thermal expansion and contributing to sea level rise.
                  " (extract-fr) part 0 of climate science

    @sen6   extent has declined significantly, with September minimums reaching record lows.
                  " (extract-fr) part 0 of climate science

    @sen7   Climate models project continued warming under all emission scenarios, with
                  " (extract-fr) part 0 of climate science

    @sen8   temperature increases ranging from 1.5 to 4.5 degrees by 2100.
                  " (extract-fr) part 0 of climate science

    @sen9   Extreme weather
                  " (extract-fr) part 0 of climate science

    @sen10   events including heatwaves, droughts, and intense precipitation are becoming
                  " (extract-fr) part 0 of climate science

    @sen11   more frequent and severe.
                  " (extract-fr) part 0 of climate science

    @sen12   Mitigation strategies focus on reducing emissions
                  " (extract-fr) part 0 of climate science

    @sen13   through renewable energy adoption, energy efficiency improvements, and carbon
                  " (extract-fr) part 0 of climate science

    @sen14   Adaptation measures include building resilient
                  " (extract-fr) part 0 of climate science

    @sen15   infrastructure, developing drought-resistant crops, and implementing early
                  " (extract-fr) part 0 of climate science

    @sen16   warning systems for extreme weather events.
                  " (extract-fr) part 0 of climate science

     -:: _sequence_ , climate science::

    # (end) ************

    # Final fraction 80.0 of requested 60.0
    # Selected 16 samples of 20

## Step 2: Intentionality Scoring

The `score_sentence` function measures how “intentional” or meaningful a
sentence is based on word frequency patterns. Let’s compare different
text styles:

``` julia
# Build vocabularies for different texts
emotional_text = """
I absolutely love the feeling of warm sunshine on my face! It fills me with
incredible joy and happiness. Nothing beats the wonderful sensation of a
beautiful summer morning. I feel so grateful and blessed to experience these
magical moments. My heart overflows with pure delight and contentment.
"""

technical_text = """
The TCP three-way handshake establishes a reliable connection between client
and server. The client sends a SYN packet with an initial sequence number.
The server responds with SYN-ACK, acknowledging the client's sequence number
and providing its own. The client completes the handshake by sending an ACK
packet. This mechanism ensures both endpoints are ready for bidirectional
data transfer with guaranteed delivery and ordering.
"""

for (label, text) in [("Factual/Climate", factual_text),
                       ("Emotional", emotional_text),
                       ("Technical/TCP", technical_text)]
    sentences = SemanticSpacetime.split_sentences(SemanticSpacetime.clean_text(text))
    vocab = SemanticSpacetime.build_vocab(sentences)
    scores = [score_sentence(s, vocab) for s in sentences]
    avg = isempty(scores) ? 0.0 : sum(scores) / length(scores)
    println("$label: $(length(sentences)) sentences, avg score $(round(avg, digits=2))")
end
```

    Factual/Climate: 20 sentences, avg score 11.08
    Emotional: 8 sentences, avg score 4.64
    Technical/TCP: 9 sentences, avg score 16.51

Score individual sentences to see which carry the most information:

``` julia
sentences = SemanticSpacetime.split_sentences(SemanticSpacetime.clean_text(factual_text))
vocab = SemanticSpacetime.build_vocab(sentences)

println("Sentence intentionality scores:")
for (i, sent) in enumerate(sentences)
    score = score_sentence(sent, vocab)
    short = sent[1:min(60, length(sent))]
    println("  [$i] $(round(score, digits=2)): $short...")
end
```

    Sentence intentionality scores:
      [1] 31.11: The global mean surface temperature has increased by approxi...
      [2] 5.83: Celsius since the pre-industrial era....
      [3] 9.91: This warming is primarily driven by...
      [4] 9.94: anthropogenic greenhouse gas emissions, particularly carbon ...
      [5] 0.0: fuel combustion....
      [6] 20.07: The ocean has absorbed more than 90 percent of the excess he...
      [7] 16.09: leading to thermal expansion and contributing to sea level r...
      [8] 2.98: Arctic sea ice...
      [9] 8.4: extent has declined significantly, with September minimums r...
      [10] 10.94: Climate models project continued warming under all emission ...
      [11] 27.78: temperature increases ranging from 1.5 to 4.5 degrees by 210...
      [12] 13.92: Extreme weather...
      [13] 7.21: events including heatwaves, droughts, and intense precipitat...
      [14] 11.19: more frequent and severe....
      [15] 0.0: Mitigation strategies focus on reducing emissions...
      [16] 25.11: through renewable energy adoption, energy efficiency improve...
      [17] 0.0: capture technologies....
      [18] 0.0: Adaptation measures include building resilient...
      [19] 7.21: infrastructure, developing drought-resistant crops, and impl...
      [20] 13.92: warning systems for extreme weather events....

## Step 3: Extract Significant Sentences

The `extract_significant_sentences` function combines running and static
intentionality analysis to select the most meaningful sentences:

``` julia
selected = extract_significant_sentences(factual_text; target_percent=40.0)
println("Selected $(length(selected)) of $(length(sentences)) sentences:\n")
for (i, sent) in enumerate(selected)
    println("  $i. $sent")
end
```

    Selected 13 of 20 sentences:

      1. The global mean surface temperature has increased by approximately 1.1 degrees
      2. anthropogenic greenhouse gas emissions, particularly carbon dioxide from fossil
      3. The ocean has absorbed more than 90 percent of the excess heat,
      4. leading to thermal expansion and contributing to sea level rise.
      5. extent has declined significantly, with September minimums reaching record lows.
      6. Climate models project continued warming under all emission scenarios, with
      7. temperature increases ranging from 1.5 to 4.5 degrees by 2100.
      8. Extreme weather
      9. events including heatwaves, droughts, and intense precipitation are becoming
      10. more frequent and severe.
      11. through renewable energy adoption, energy efficiency improvements, and carbon
      12. infrastructure, developing drought-resistant crops, and implementing early
      13. warning systems for extreme weather events.

## Step 4: Compile Auto-Generated N4L

Now compile the generated N4L into a graph and explore it:

``` julia
store = MemoryStore()
try
    cr = compile_n4l_string!(store, n4l_output; config_dir=SST_CONFIG)
    println("Compiled: $(cr.nodes_created) nodes, $(cr.edges_created) edges")
    println("Chapters: ", join(cr.chapters, ", "))
catch e
    println("Compilation note: ", e)
end

println("Graph: $(node_count(store)) nodes, $(link_count(store)) links")
```

    Compiled: 17 nodes, 31 edges
    Chapters: Samples from climate science
    Graph: 17 nodes, 62 links

## Step 5: Search the Knowledge Graph

Search the auto-generated graph for key concepts:

``` julia
for query in ["temperature", "carbon", "ocean", "emission", "climate"]
    results = mem_search_text(store, query)
    println("Search '$query': $(length(results)) results")
    for n in results[1:min(2, length(results))]
        short = n.s[1:min(50, length(n.s))]
        println("  '$(short)...'")
    end
end
```

    Search 'temperature': 2 results
      'temperature increases ranging from 1.5 to 4.5 degr...'
      'The global mean surface temperature has increased ...'
    Search 'carbon': 2 results
      'anthropogenic greenhouse gas emissions, particular...'
      'through renewable energy adoption, energy efficien...'
    Search 'ocean': 1 results
      'The ocean has absorbed more than 90 percent of the...'
    Search 'emission': 3 results
      'anthropogenic greenhouse gas emissions, particular...'
      'Mitigation strategies focus on reducing emissions...'
    Search 'climate': 2 results
      'part 0 of climate science...'
      'Climate models project continued warming under all...'

## Step 6: Compare Text Styles

Generate N4L from different text styles and compare the results:

``` julia
for (label, text) in [("Emotional", emotional_text), ("Technical", technical_text)]
    n4l = text_to_n4l(text; chapter=lowercase(label), target_percent=50.0)
    s = MemoryStore()
    try
        cr = compile_n4l_string!(s, n4l; config_dir=SST_CONFIG)
        println("$label: $(cr.nodes_created) nodes, $(cr.edges_created) edges")
    catch e
        println("$label: compilation note - $e")
    end
    println("  Graph: $(node_count(s)) nodes, $(link_count(s)) links")
end
```

    Emotional: 5 nodes, 7 edges
      Graph: 5 nodes, 14 links
    Technical: 6 nodes, 9 edges
      Graph: 6 nodes, 18 links

## Step 7: Graph Analysis of Extracted Knowledge

``` julia
if node_count(store) > 0
    adj = SemanticSpacetime.AdjacencyMatrix()
    for (nptr, node) in store.nodes
        for links in node.incidence
            for link in links
                SemanticSpacetime.add_edge!(adj, nptr, link.dst, Float64(link.wgt))
            end
        end
    end

    if !isempty(adj.nodes)
        println(graph_summary(adj))

        centrality = eigenvector_centrality(adj; max_iter=100, tol=1e-6)
        ranked = sort(collect(centrality), by=x -> x.second, rev=true)
        println("\nMost central nodes in extracted knowledge:")
        for (nptr, score) in ranked[1:min(6, length(ranked))]
            node = mem_get_node(store, nptr)
            if node !== nothing
                label = node.s[1:min(50, length(node.s))]
                println("  $(rpad(label, 52)) $(round(score, digits=4))")
            end
        end
    end
end
```

    Graph Summary
    ─────────────
      Nodes:   17
      Links:   62 (directed)
      Sources: 0
      Sinks:   0
      Top centrality:
        (4,2)  1.0000
        (4,9)  0.3268
        (2,1)  0.3268
        (4,10)  0.3268
        (4,8)  0.3268


    Most central nodes in extracted knowledge:
      part 0 of climate science                            1.0
      temperature increases ranging from 1.5 to 4.5 degr   0.3268
      Extreme weather                                      0.3268
      events including heatwaves, droughts, and intense    0.3268
      Climate models project continued warming under all   0.3268
      more frequent and severe.                            0.3268

## Summary

The text→knowledge pipeline:

| Step | Function | Purpose |
|----|----|----|
| 1 | `text_to_n4l(text)` | Auto-generate N4L from plain text |
| 2 | `score_sentence(text, vocab)` | Measure intentionality of individual sentences |
| 3 | `extract_significant_sentences(text)` | Select the most meaningful sentences |
| 4 | `compile_n4l_string!(store, n4l)` | Build a knowledge graph from generated N4L |
| 5 | `mem_search_text(store, query)` | Search the resulting graph |
| 6 | `eigenvector_centrality(adj)` | Analyse structural importance |

This pipeline transforms unstructured text into a queryable, analysable
knowledge graph — automatically identifying and preserving the most
significant information.
