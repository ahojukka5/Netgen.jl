using Documenter
using Delone
using OodiCore

makedocs(
    modules = [Delone, OodiCore],
    sitename = "Delone.jl",
    authors = "Jukka Aho",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        size_threshold = nothing,
    ),
    pages = [
        "Home" => "index.md",
        "Tutorial" => "tutorial.md",
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
        "Concepts" => [
            "MeshOptions" => "mesh_options.md",
            "Sessions & snapshots" => "sessions_snapshots.md",
            "Introspection contract" => "introspection_contract.md",
            "Internals escape hatch" => "internals_escape_hatch.md",
            "Handles, ownership & GC" => "handles_gc.md",
        ],
        "Reference" => [
            "Geometry" => "reference/geometry.md",
            "Mesh generation & I/O" => "reference/meshing.md",
            "Mesh introspection & LLM contract" => "reference/mesh_introspection.md",
            "Validation, quality & meshability" => "reference/validation_quality.md",
            "Refinement" => "reference/refinement.md",
            "Local mesh sizing" => "reference/local_sizing.md",
            "Mesh surgery & spatial search" => "reference/mesh_surgery.md",
            "Multigrid hierarchy" => "reference/hierarchy.md",
            "Live session" => "reference/session.md",
            "Snapshots & Oodi readiness" => "reference/snapshots.md",
            "Export & preview" => "reference/export.md",
            "Tags & regions" => "reference/tags.md",
            "hp-adaptivity & FEM geometry" => "reference/hp_fem.md",
            "Topology tables & partition" => "reference/partition.md",
            "Constants" => "reference/constants.md",
        ],
        "Development" => "development.md",
    ],
    checkdocs = :exported,
    warnonly = [:missing_docs, :docs_block],
    doctest = true,
)

deploydocs(
    repo = "github.com/ahojukka5/Delone.jl.git",
    devbranch = "master",
    push_preview = true,
)
