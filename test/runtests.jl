using Delone
const I = Delone.Internals
using Test

# Monge.jl (CAD modeling, package "Monge") is a test dependency (`Pkg.test()`).
# When running this file directly in the monorepo, add the sibling package if needed.
const _OC_PATH = normpath(@__DIR__, "..", "..", "Monge.jl")
if Base.find_package("Monge") === nothing && isdir(_OC_PATH)
    if Base.find_package("Pkg") !== nothing
        import Pkg
        Pkg.develop(Pkg.PackageSpec(path=_OC_PATH))
    end
end
using Monge

const STEP     = joinpath(@__DIR__, "fixtures", "frame.step")
const CYLINDER = joinpath(@__DIR__, "fixtures", "cylinder.brep")  # unit cylinder, r=1, h=2

@testset "Delone.jl" begin
    # Delone mesh core
    include("mesh.jl")
    include("mesh_api.jl")
    include("llm_feedback.jl")
    include("refinement.jl")
    include("hierarchy.jl")
    include("session.jl")
    include("tags_hp.jl")
    include("hp_apply.jl")
    include("fem.jl")
    include("brep_bridge.jl")
    include("geom2d.jl")
    include("extras.jl")
    include("stl.jl")
    include("gprim.jl")
    include("mesh2.jl")
    include("ngx2.jl")
end
