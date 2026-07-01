using Documenter
using Delone

makedocs(
    modules = [Delone],
    sitename = "Delone.jl",
    authors = "Jukka Aho",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        size_threshold = nothing,
    ),
    pages = [
        "Home" => "index.md",
        "Upstream documentation" => "external.md",
        "Wrapped capabilities" => "capabilities.md",
        "Not yet wrapped" => "limitations.md",
        "Examples" => [
            "Building geometry" => "examples/geometry.md",
            "Meshing" => "examples/meshing.md",
            "Refinement" => "examples/refinement.md",
            "Mesh hierarchies & sessions" => "examples/hierarchy.md",
            "Structured reports & introspection" => "examples/introspection.md",
            "Tags, hp-adaptivity & FEM data" => "examples/tags_hp_fem.md",
        ],
        "Development" => "development.md",
    ],
    checkdocs = :none,
    warnonly = [:cross_references, :missing_docs],
)
