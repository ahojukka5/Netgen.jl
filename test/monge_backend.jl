# generate_mesh(body::Monge.Body; ...) (src/interop.jl): a single,
# backend-agnostic entry point for an in-memory CAD body -- no manual
# to_brep_string/occ_geometry_from_brep_string/gmsh_mesh_from_brep_string
# plumbing needed. Monge is a real [deps] entry (not a weakdep -- see
# test/runtests.jl's Aqua exemption comment), so this file needs no
# skip-guard for the Netgen half; the Gmsh half is still guarded since Gmsh
# genuinely is optional.
@testset "generate_mesh(::Monge.Body) — Netgen backend" begin
    body = box(1.0, 1.0, 1.0)
    m = generate_mesh(body; maxh=0.3)
    @test I.GetNP(m) > 0
    @test I.GetNE(m) > 0
    bbox = mesh_bounding_box(m)
    @test isapprox(collect(bbox.min), [0.0, 0.0, 0.0]; atol=1e-8)
    @test isapprox(collect(bbox.max), [1.0, 1.0, 1.0]; atol=1e-8)

    res = generate_mesh(body; maxh=0.3, result=true)
    @test res isa MeshGenerationResult
end

@testset "generate_mesh(::Monge.Body; backend=:gmsh) — Gmsh backend" begin
    if Base.find_package("Gmsh") === nothing
        @info "Gmsh not installed; skipping the Gmsh half of this verification"
    else
        @eval using Gmsh
        body = box(1.0, 1.0, 1.0)
        s = generate_mesh(body; maxh=0.3, backend=:gmsh)
        @test s isa MeshLevelSnapshot{3,Float64,Int32}
        @test isapprox(vec(minimum(s.coordinates, dims=2)), [0.0, 0.0, 0.0]; atol=1e-8)
        @test isapprox(vec(maximum(s.coordinates, dims=2)), [1.0, 1.0, 1.0]; atol=1e-8)

        @test_throws ArgumentError generate_mesh(body; maxh=0.3, backend=:gmsh, result=true)
        @test_throws ArgumentError generate_mesh(
            body; options=MeshOptions(maxh=0.3), backend=:gmsh)
    end
end

@testset "generate_mesh(::Monge.Body): unknown backend" begin
    body = box(1.0, 1.0, 1.0)
    @test_throws ArgumentError generate_mesh(body; maxh=0.3, backend=:bogus)
end
