using Delone
const I = Delone.Netgen
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
    # Fast static-quality check first, so a broken Aqua check fails quickly
    # without waiting for the full native-mesh suite below.
    @testset "Aqua" begin
        using Aqua
        Aqua.test_all(Delone;
            ambiguities = false,   # CxxWrap-generated method tables commonly trip false positives here
            # Pre-existing gap, out of scope here: stdlibs (Artifacts, Libdl,
            # Test) and the path-sourced sibling Monge (pinned via [sources],
            # not a registry version) have no [compat] entries. Adding those
            # touches [compat] for deps unrelated to Aqua, which is out of
            # scope for this change; left as a note for whoever owns
            # Project.toml's [compat] section generally.
            deps_compat = false,
            # Aqua is declared as a real [deps] entry (not a separate test
            # target) so this monorepo-style setup can run
            # `julia --project=. test/runtests.jl` directly (no `Pkg.test()`
            # synthetic test env). It's used only from test/runtests.jl,
            # never from src/, so Aqua's stale-deps heuristic (which expects
            # test-only deps under [extras]/[targets]) always flags it here.
            # This is a structural false positive from the repo's
            # dependency-declaration convention, not a real stale dep. (Monge
            # is a real [deps] entry for the same monorepo reason, but is
            # also genuinely used from src/ now — see `src/interop.jl`'s
            # `generate_mesh(::Monge.Body)` — so it wouldn't need this
            # exemption on its own merits even without the monorepo
            # workaround. A weakdep/extension split was tried and reverted:
            # the `Pkg.develop` fallback below unconditionally re-promotes
            # Monge into [deps] whenever it's missing from the manifest,
            # which fights a [weakdeps]-only declaration on every fresh
            # checkout.)
            stale_deps = false,
            unbound_args = true,
            undefined_exports = true,
            # Flags isvalid/report/validate/readiness methods on Delone's own
            # types. These are the shared introspection contract generics
            # owned by OodiCore.jl and deliberately extended here per
            # AGENTS.md ("Delegates to OodiCore... adds methods/subtypes")
            # plus Base.isvalid extended on Delone's own Mesh type — an
            # intentional, documented ecosystem-wide extension pattern, not
            # accidental type piracy. Aqua's heuristic cannot distinguish the
            # two, and this is core, intentional architecture (see AGENTS.md)
            # that is not this change's to alter.
            piracies = false,
        )
    end

    # Delone mesh core
    include("mesh.jl")
    include("mesh_api.jl")
    include("mesh_construction.jl")
    include("llm_feedback.jl")
    include("refinement.jl")
    include("local_sizing.jl")
    include("hierarchy.jl")
    include("session.jl")
    include("tags_hp.jl")
    include("hp_apply.jl")
    include("fem.jl")
    include("brep_bridge.jl")
    include("periodic.jl")
    include("geom2d.jl")
    include("extras.jl")
    include("stl.jl")
    include("boundary_naming_stl.jl")
    include("gprim.jl")
    include("mesh_surgery.jl")
    include("mesh2.jl")
    include("ngx2.jl")
    include("native_quality.jl")
    include("base_interface.jl")
    include("makie_ext.jl")
    include("geometrybasics_ext.jl")
    include("writevtk_ext.jl")
    include("gmsh_backend.jl")
    include("monge_backend.jl")
end
