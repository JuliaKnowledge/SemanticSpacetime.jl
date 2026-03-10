using Documenter
using SemanticSpacetime

makedocs(
    sitename = "SemanticSpacetime.jl",
    modules = [SemanticSpacetime],
    remotes = nothing,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "API Reference" => "api.md",
    ],
    checkdocs = :exports,
    warnonly = true,
)
