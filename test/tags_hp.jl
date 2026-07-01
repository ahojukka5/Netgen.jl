# Region/tag extraction, hp-readiness helpers, and partition contract.

@testset "volume_tetrahedra / dimension-checked extraction (3D)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    V = volume_tetrahedra(m)
    @test size(V) == (4, I.GetNE(m))
    @test all(1 .<= V .<= I.GetNP(m))
    # 2D-only extractors must refuse a 3D mesh
    @test_throws ArgumentError triangles2d(m)
    @test_throws ArgumentError segments2d(m)
end

@testset "triangles2d / segments2d (2D) + 3D refusal of volume_tetrahedra" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    m = generate_mesh(geometry2d(disk); maxh=0.4)
    T = triangles2d(m)
    @test size(T) == (3, I.GetNSE(m))
    @test all(1 .<= T .<= I.GetNP(m))
    S = segments2d(m)
    @test size(S) == (2, I.GetNSeg(m))
    @test all(1 .<= S .<= I.GetNP(m))
    @test_throws ArgumentError volume_tetrahedra(m)
end

@testset "material and boundary name extraction (3D fixture)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    mats = material_names(m)
    @test mats isa Dict{Int32,String}
    @test length(mats) == I.GetNDomains(m)
    @test haskey(mats, Int32(1))
    bnames = boundary_names(m)
    @test bnames isa Dict{Int32,String}
    @test length(bnames) == I.GetNFD(m)
    # region id vectors line up with the name dictionaries
    cr = cell_regions(m)
    @test length(cr) == I.GetNE(m)
    @test all(r -> haskey(mats, r), cr)
    br = boundary_regions(m)
    @test length(br) == I.GetNSE(m)
    @test all(r -> haskey(bnames, r), br)
end

@testset "element-order helpers on a generated + second-order mesh" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    eos = element_orders(m)
    @test length(eos) == I.GetNE(m)
    @test all(eos .>= 1)
    @test element_order(m) == maximum(eos)
    seos = surface_element_orders(m)
    @test length(seos) == I.GetNSE(m)
    @test all(seos .>= 1)
    @test surface_element_order(m) >= 1
    # hp levels: sentinel -1 for a non-hp mesh, shape 3×NE
    L = hp_element_levels(m)
    @test size(L) == (3, I.GetNE(m))
    @test all(L .== -1)
    # curving to second order keeps orders sensible (>= 1)
    make_second_order!(m)
    @test all(element_orders(m) .>= 1)
end

@testset "surface_element_orders refuses a 2D mesh" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    m = generate_mesh(geometry2d(disk); maxh=0.4)
    @test_throws ArgumentError surface_element_orders(m)
    # element_orders still works on the 2D cells (triangles)
    @test length(element_orders(m)) == I.GetNSE(m)
end

@testset "partition contract: native_partition_hint (serial identity)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    hint = native_partition_hint(m)
    np = I.GetNP(m)
    @test hint.global_vertex_ids == collect(1:np)
    @test length(hint.distant_procs) == np
    @test all(isempty, hint.distant_procs)
end

@testset "per-element region names (3D)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    mats = material_names(m)
    cr = cell_regions(m)
    @test region_name_volume(m, 1) == mats[cr[1]]
    br = boundary_regions(m)
    @test region_name_surface(m, 1) == boundary_names(m)[br[1]]
end

@testset "2D tag/name behavior (documented current state, no invented names)" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    m = generate_mesh(geometry2d(disk); maxh=0.4)
    # topological region ids DO work in 2D
    cr = cell_regions(m)
    @test length(cr) == I.GetNSE(m)
    @test all(cr .>= 1)
    br = boundary_regions(m)
    @test length(br) == I.GetNSeg(m)
    @test all(br .>= 1)
    # NAMES: 2D material names are unavailable through this path (GetNDomains==0),
    # so material_names is empty. We assert the *current* behavior rather than
    # pretending support exists (see docstring/README limitation).
    mats = material_names(m)
    @test mats isa Dict{Int32,String}
    @test isempty(mats)
    @test I.GetNDomains(m) == 0
    # boundary_names returns a Dict but its keys (face-descriptor indices) are not
    # guaranteed to correspond to boundary_regions (segment indices) in 2D.
    bnames = boundary_names(m)
    @test bnames isa Dict{Int32,String}
end

@testset "README does not link the private (gitignored) audit file" begin
    readme = read(joinpath(@__DIR__, "..", "README.md"), String)
    @test !occursin("audit/NETGEN_LIVE_HIERARCHY_AND_PARTITION_CONTRACT", readme)
    @test !occursin("](audit/", readme)
    # still documents the core contract
    @test occursin("Live session", readme)
    @test occursin("Supported snapshot topology", readme)
    @test occursin("Transfer weights", readme)
    @test occursin("Partitioning responsibility", readme)
end
