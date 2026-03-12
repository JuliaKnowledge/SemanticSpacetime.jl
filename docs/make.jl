using Documenter
using SemanticSpacetime

makedocs(
    sitename = "SemanticSpacetime.jl",
    modules = [SemanticSpacetime],
    remotes = nothing,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://JuliaKnowledge.github.io/SemanticSpacetime.jl",
        repolink = "https://github.com/JuliaKnowledge/SemanticSpacetime.jl",
    ),
    pages = [
        "Home" => "index.md",
        "Guide" => [
            "Getting Started" => "getting_started.md",
            "Storage Backends" => "storage.md",
            "N4L Language" => "n4l.md",
            "Search & Paths" => "search.md",
            "Graph Analysis" => "graph_analysis.md",
            "Visualization" => "visualization.md",
        ],
        "API Reference" => [
            "Types & Constants" => "api/types.md",
            "Storage" => "api/stores.md",
            "Arrows & Contexts" => "api/arrows_contexts.md",
            "Graph Analysis" => "api/graph.md",
            "Search & Paths" => "api/search.md",
            "N4L" => "api/n4l.md",
            "RDF Integration" => "api/rdf.md",
            "Text Analysis" => "api/text.md",
            "Visualization" => "api/visualization.md",
            "HTTP Server" => "api/server.md",
            "Utilities" => "api/utilities.md",
        ],
    ],
    checkdocs = :exports,
    warnonly = true,
)

deploydocs(
    repo = "github.com/JuliaKnowledge/SemanticSpacetime.jl.git",
    devbranch = "main",
    push_preview = true,
)
