using Documenter
using SemanticSpacetime

# Copy rendered vignette markdown into docs/src/vignettes/
const VIGNETTES_SRC = joinpath(@__DIR__, "..", "vignettes")
const VIGNETTES_DST = joinpath(@__DIR__, "src", "vignettes")
mkpath(VIGNETTES_DST)

vignette_pages = Pair{String,String}[]
for dir in sort(readdir(VIGNETTES_SRC))
    src_dir = joinpath(VIGNETTES_SRC, dir)
    isdir(src_dir) || continue
    md_file = joinpath(src_dir, "$dir.md")
    isfile(md_file) || continue
    dst_file = joinpath(VIGNETTES_DST, "$dir.md")
    cp(md_file, dst_file; force=true)
    # Convert directory name to a nice title: "01-getting-started" → "Getting Started"
    title = join(uppercasefirst.(split(replace(dir, r"^\d+-" => ""), "-")), " ")
    push!(vignette_pages, title => "vignettes/$dir.md")
end

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
        "Vignettes" => vignette_pages,
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
