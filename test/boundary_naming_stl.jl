# Naming setters (write side of material_names / boundary_names) + STLParameters
# reachability investigation. See src/tags.jl docstrings for the persistence
# subtlety around GetFaceDescriptor (const) vs GetFaceDescriptorMut (mutable).

# Defined locally (not relying on test/stl.jl's copy) so this file has no
# ordering dependency on where it is `include`d from test/runtests.jl.
const _BNS_STL_TET = joinpath(@__DIR__, "fixtures", "tet.stl")

@testset "set_material_name! persists into material_names" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test material_names(m)[Int32(1)] != "renamed_material"
    @test set_material_name!(m, 1, "renamed_material") === m
    @test material_names(m)[Int32(1)] == "renamed_material"
    @test_throws ArgumentError set_material_name!(m, 0, "x")
    @test_throws ArgumentError set_material_name!(m, I.GetNDomains(m) + 1, "x")
end

@testset "set_boundary_name! persists into boundary_names (GetFaceDescriptorMut path)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    before = boundary_names(m)[Int32(1)]
    @test before != "wall"
    @test set_boundary_name!(m, 1, "wall") === m
    @test boundary_names(m)[Int32(1)] == "wall"
    @test_throws ArgumentError set_boundary_name!(m, 0, "x")
    @test_throws ArgumentError set_boundary_name!(m, I.GetNFD(m) + 1, "x")
end

@testset "rename_materials! / rename_boundaries! bulk setters" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nd = I.GetNDomains(m)
    nfd = I.GetNFD(m)

    mat_updates = Dict{Int32,String}(Int32(i) => "mat_$i" for i in 1:nd)
    @test rename_materials!(m, mat_updates) === m
    mats = material_names(m)
    for i in 1:nd
        @test mats[Int32(i)] == "mat_$i"
    end

    # rename only a couple of boundaries; others should remain untouched
    bnd_updates = Dict{Int32,String}(Int32(1) => "inlet", Int32(min(2, nfd)) => "outlet")
    @test rename_boundaries!(m, bnd_updates) === m
    bnames = boundary_names(m)
    @test bnames[Int32(1)] == "inlet"
    @test bnames[Int32(min(2, nfd))] == "outlet"
end

@testset "GetFaceDescriptor (const) vs GetFaceDescriptorMut (mutable) — documented persistence gotcha" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    # The const-ref accessor exists and can be read from, but Netgen.SetBCName
    # has no method accepting a ConstCxxRef{FaceDescriptor} -- confirming that
    # set_boundary_name! must go through GetFaceDescriptorMut to persist.
    fd_const = I.GetFaceDescriptor(m, 1)
    @test I.GetBCName(fd_const) isa AbstractString
    @test_throws MethodError I.SetBCName(fd_const, "should_not_apply")
end

@testset "STLParameters: reachable object, but not wired into STL meshing (documented gap)" begin
    # STLParameters getters/setters (yangle!, contyangle!, ...) are wrapped and
    # functional as a standalone value object (see test/stl.jl).
    p = I.STLParameters()
    I.yangle!(p, 1.0)
    @test I.yangle(p) == 1.0

    # But no Julia-reachable GenerateMesh overload accepts an STLParameters:
    # only (NetgenGeometry|CSG2d|STLGeometry, Mesh, MeshingParameters) exist.
    sigs = [m.sig for m in methods(I.GenerateMesh)]
    @test !any(sig -> occursin("STLParameters", string(sig)), sigs)

    # Root cause (traced in netgen/libsrc/stlgeom/stlgeom.cpp): the wrapped
    # STLGeometry::GenerateMesh(mesh, mparam) override internally copies a
    # C++ *global* `extern STLParameters stlparam` singleton -- it does not
    # accept a caller-supplied STLParameters. Upstream Netgen's own Python
    # bindings (stlgeom/python_stl.cpp) bypass this override entirely and
    # call the lower-level `STLMeshingDummy(geo, mesh, mp, stlparam)` free
    # function directly with a locally-built STLParameters. That function is
    # not exposed by NetgenCxxWrap_jll, so there is currently no Julia-reachable
    # connection point between STLParameters and actual STL meshing behavior.
    stl = load_stl(_BNS_STL_TET)
    m = I.new_mesh()
    mp = I.MeshingParameters()
    I.maxh!(mp, 40.0)
    status = I.GenerateMesh(stl, m, mp)  # always uses global defaults, ignores `p`
    @test status == 0
    @test I.GetNP(m) == 4
end
