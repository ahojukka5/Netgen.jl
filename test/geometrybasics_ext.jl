# DeloneGeometryBasicsExt: only exercised when GeometryBasics is actually
# installed in this environment (the extension itself only needs the
# `GeometryBasics` weakdep to be *defined* — see Project.toml
# [weakdeps]/[extensions]). The main test suite must not gain a hard
# dependency on GeometryBasics just to keep this file green, so everything
# below is guarded (mirrors test/makie_ext.jl's guard pattern).
@testset "DeloneGeometryBasicsExt (GeometryBasics.Mesh bridge)" begin
    if Base.find_package("GeometryBasics") === nothing
        @info "GeometryBasics not installed; skipping DeloneGeometryBasicsExt " *
              "verification (the extension itself still loads fine once " *
              "GeometryBasics is available)"
        @test true   # keep the testset non-empty/non-vacuous under `--fail-fast`-style runners
    else
        @eval using GeometryBasics

        @test Base.get_extension(Delone, :DeloneGeometryBasicsExt) !== nothing

        geom = load_step(STEP)
        s = mesh_session(geom; maxh=40.0)
        snap3 = level_snapshot(s, 1)
        @test snap3 isa MeshLevelSnapshot{3}

        gm3 = GeometryBasics.Mesh(snap3)
        @test gm3 isa GeometryBasics.Mesh
        @test length(GeometryBasics.coordinates(gm3)) == size(snap3.coordinates, 2)
        @test length(GeometryBasics.faces(gm3)) == size(snap3.surface_connectivity, 2)
        @test eltype(GeometryBasics.coordinates(gm3)) <: GeometryBasics.Point{3}

        hs = hierarchy_snapshot(s)
        @test hs isa MeshHierarchySnapshot
        gm3_h = GeometryBasics.Mesh(hs)
        @test gm3_h isa GeometryBasics.Mesh
        @test length(GeometryBasics.faces(gm3_h)) == size(hs.levels[end].surface_connectivity, 2)

        # 2D snapshot path. `Circle` is disambiguated to `Delone.Circle`: some
        # GeometryBasics-adjacent packages re-export a `Circle` of their own,
        # which would otherwise collide with Delone's 2D CSG primitive of the
        # same name.
        disk = Delone.Circle(0.0, 0.0, 1.0, "disk", "circle")
        geo2d = geometry2d(disk)
        s2 = mesh_session(geo2d; maxh=0.4)
        snap2 = level_snapshot(s2, 1)
        @test snap2 isa MeshLevelSnapshot{2}

        gm2 = GeometryBasics.Mesh(snap2)
        @test gm2 isa GeometryBasics.Mesh
        @test length(GeometryBasics.coordinates(gm2)) == size(snap2.coordinates, 2)
        @test length(GeometryBasics.faces(gm2)) == size(snap2.volume_connectivity, 2)
        @test eltype(GeometryBasics.coordinates(gm2)) <: GeometryBasics.Point{2}
    end
end
