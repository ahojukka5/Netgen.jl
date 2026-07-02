# LLM-friendly meshing feedback loop: structured reports, hierarchy, snapshots.

@testset "MeshOptions validation" begin
    opts = MeshOptions(maxh=2.0, minh=0.1, grading=0.3)
    @test opts.maxh == 2.0
    @test validate_options!(opts) === opts
    @test_throws ArgumentError validate_options!(MeshOptions(maxh=-1.0))
    @test_throws ArgumentError validate_options!(MeshOptions(maxh=1.0, minh=2.0))
end

@testset "MeshOptions validation: remaining ArgumentError branches (options.jl)" begin
    # minh <= 0 (distinct from the minh > maxh branch above)
    @test_throws ArgumentError validate_options!(MeshOptions(maxh=1.0, minh=-0.5))
    # grading < 0
    @test_throws ArgumentError validate_options!(MeshOptions(maxh=1.0, grading=-0.1))
    # dimension not in (2, 3)
    @test_throws ArgumentError validate_options!(MeshOptions(maxh=1.0, dimension=4))
    # local_size entry: unsupported type (neither NamedTuple nor length>=2 Tuple)
    @test_throws ArgumentError validate_options!(MeshOptions(maxh=1.0, local_size=Any[5]))
    # local_size entry: NamedTuple missing `point`
    @test_throws ArgumentError validate_options!(MeshOptions(maxh=1.0, local_size=Any[(h=1.0,)]))
    # local_size entry: radius <= 0
    @test_throws ArgumentError validate_options!(
        MeshOptions(maxh=1.0, local_size=Any[(point=(0.0, 0.0, 0.0), h=1.0, radius=-1.0)]))
    # local_size entry: levels < 1
    @test_throws ArgumentError validate_options!(
        MeshOptions(maxh=1.0, local_size=Any[(point=(0.0, 0.0, 0.0), h=1.0, levels=0)]))
end

@testset "generate_mesh structured result (3D STEP)" begin
    geom = load_step(STEP)
    opts = MeshOptions(maxh=40.0, grading=0.3)
    result = generate_mesh(geom; options=opts, result=true)
    @test result isa MeshGenerationResult
    @test result.success
    @test result.mesh !== nothing
    @test result.options.maxh == 40.0
    @test num_cells(result.mesh) > 0
    @test result.elapsed_seconds >= 0
    m = mesh(result)
    @test num_nodes(m) == num_nodes(result.mesh)
end

@testset "generate_mesh legacy maxh path" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test num_cells(m) > 0
end

@testset "generate_mesh failure report (null geometry)" begin
    opts = MeshOptions(maxh=1.0)
    result = generate_mesh_result(nothing, opts)
    @test !result.success
    @test result.mesh === nothing
    @test result.diagnostics.failure_stage == :geometry_import
    @test !isempty(result.diagnostics.messages)
end

@testset "mesh_report / validate / quality (3D)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    r = mesh_report(m)
    @test r isa MeshReport
    @test r.validation.valid
    @test r.validation.node_count > 0
    @test r.validation.element_count > 0
    @test isvalid(m)
    q = quality(m)
    @test isfinite(q.min_quality)
    @test isfinite(q.mean_quality)
    @test q.min_edge_length > 0
    @test q.max_edge_length >= q.min_edge_length
    # printable
    @test length(string(r)) > 20
end

@testset "tag_report (3D STEP)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    tr = Delone.tag_report(m)
    @test tr isa MeshTagReport
    @test length(string(tr)) > 10
end

@testset "2D disk: mesh, report, hierarchy" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
    geom = geometry2d(disk)
    opts = MeshOptions(maxh=0.5)
    m = generate_mesh(geom; options=opts)
    r = mesh_report(m)
    @test r.validation.dimension == 2
    @test r.validation.valid
    @test r.validation.element_count > 0
    q = quality(m)
    @test isfinite(q.mean_quality)

    h = mesh_hierarchy(geom; maxh=0.5, levels=1)
    refine!(h; mode=:uniform, result=true)
    hr = hierarchy_report(h)
    @test hr.nlevels == 2
    @test hr.levels[2].element_count > hr.levels[1].element_count
    @test hr.transfers[1].inherited_node_count > 0
    @test length(string(hr)) > 20
end

@testset "refine!/refine_session! ArgumentError branches (refinement_result.jl)" begin
    geom = load_step(STEP)
    h = mesh_hierarchy(geom; maxh=40.0, levels=1)
    @test_throws ArgumentError refine!(h; mode=:marked)  # marked_elements required for :marked
    @test_throws ArgumentError refine!(h; mode=:bogus)   # unsupported mode

    s = mesh_session(geom; maxh=40.0)
    @test_throws ArgumentError refine_session!(s; mode=:marked)
    @test_throws ArgumentError refine_session!(s; mode=:bogus)
end

@testset "level_report/transfer_report ArgumentError branches (hierarchy_report.jl)" begin
    geom = load_step(STEP)
    h = mesh_hierarchy(geom; maxh=40.0, levels=1)
    refine!(h; mode=:uniform)  # -> 2 levels

    @test_throws ArgumentError level_report(h, 0)
    @test_throws ArgumentError level_report(h, 3)
    @test_throws ArgumentError transfer_report(h, 2, 2)   # fine_level != coarse_level + 1
    @test_throws ArgumentError transfer_report(h, 2, 3)   # fine_level out of range (only 2 levels)
    @test_throws ArgumentError level_report(42, 1)        # not a MeshHierarchy/Session
end

@testset "session hierarchy report and Oodi readiness" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    request_uniform_refinement!(s)
    hr = hierarchy_report(s)
    @test hr.nlevels == 2
    @test hr.generation == generation(s)

    ready = oodi_snapshot_readiness(s)
    @test ready isa OodiSnapshotReadiness
    @test ready.dimension == 3
    @test ready.hierarchy_levels == 2
    @test ready.parent_node_transfers == :available
    @test length(string(ready)) > 20

    snap = hierarchy_snapshot(s)
    @test length(snap.levels) == 2
    @test length(snap.transfers) == 1
end

@testset "refine_session! structured result" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    res = refine_session!(s; mode=:uniform, result=true)
    @test res isa RefinementResult
    @test res.success
    @test res.new_level_count == 2
    @test res.new_element_count > res.old_element_count
end

@testset "meshability_report" begin
    geom = load_step(STEP)
    opts = MeshOptions(maxh=40.0)
    mr = Delone.meshability_report(geom; options=opts)
    @test mr.likely_meshable == true
    @test !isempty(mr.suggestions)
end

@testset "export_vtk, export_obj, and export_svg_2d (real content, not just smoke)" begin
    # Parse the ASCII VTK legacy header lines this exporter writes (see
    # src/export_mesh.jl: `POINTS <n> double` and `CELLS <n> <total>`).
    function _vtk_header(path)
        points_n = cells_n = cells_total = nothing
        for l in readlines(path)
            if (mm = match(r"^POINTS\s+(\d+)", l)) !== nothing
                points_n = parse(Int, mm.captures[1])
            elseif (mm = match(r"^CELLS\s+(\d+)\s+(\d+)", l)) !== nothing
                cells_n = parse(Int, mm.captures[1])
                cells_total = parse(Int, mm.captures[2])
            end
        end
        return (; points_n, cells_n, cells_total)
    end

    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    ntets = num_cells(m)           # 3D top-dimensional cells (tetrahedra)
    nsurf = num_boundary_facets(m) # 3D boundary triangles
    nnodes = num_nodes(m)

    # Default: include_volume=true, include_surface=true -> tets (4 verts,
    # VTK_TETRA) followed by boundary triangles (3 verts, VTK_TRIANGLE).
    vtk = tempname() * ".vtk"
    export_vtk(m, vtk)
    @test isfile(vtk)
    @test occursin("UNSTRUCTURED_GRID", read(vtk, String))
    h = _vtk_header(vtk)
    @test h.points_n == nnodes
    @test h.cells_n == ntets + nsurf
    @test h.cells_total == 4 * ntets + 3 * nsurf + (ntets + nsurf)
    rm(vtk; force=true)

    # include_surface=false -> volume-only subset actually written (tets only)
    vtk_vol = tempname() * ".vtk"
    export_vtk(m, vtk_vol; include_surface=false)
    hv = _vtk_header(vtk_vol)
    @test hv.cells_n == ntets
    @test hv.cells_total == 5 * ntets
    rm(vtk_vol; force=true)

    # include_volume=false -> surface-only subset actually written (boundary triangles only)
    vtk_surf = tempname() * ".vtk"
    export_vtk(m, vtk_surf; include_volume=false)
    hs = _vtk_header(vtk_surf)
    @test hs.cells_n == nsurf
    @test hs.cells_total == 4 * nsurf
    rm(vtk_surf; force=true)

    # export_obj: "v " lines == node count, "f " lines == boundary-facet count
    obj = tempname() * ".obj"
    export_obj(m, obj)
    @test isfile(obj)
    obj_lines = readlines(obj)
    @test count(l -> startswith(l, "v "), obj_lines) == nnodes
    @test count(l -> startswith(l, "f "), obj_lines) == nsurf

    # export_svg_2d: one <polygon> per domain triangle (structural check --
    # SVG is a rendering format, so element count is the meaningful invariant)
    disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
    m2 = generate_mesh(geometry2d(disk); maxh=0.5)
    ntri2d = num_cells(m2)  # 2D top-dimensional cells (domain triangles)
    svg = tempname() * ".svg"
    export_svg_2d(m2, svg)
    @test isfile(svg)
    svg_txt = read(svg, String)
    @test occursin("<svg", svg_txt)
    @test count("<polygon", svg_txt) == ntri2d
    rm(svg; force=true)
end

@testset "public reports do not expose Internals types" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    r = mesh_report(m)
    @test !(r.validation isa Delone.Internals.Mesh)
    ready = oodi_snapshot_readiness(m)
    @test !(ready isa Delone.Internals.Mesh)
end

@testset "introspection contract: report/validate/readiness" begin
    geom = load_step(STEP)

    # validate(MeshOptions) is non-throwing and structured (OodiCore.ValidationReport)
    @test isvalid(validate(MeshOptions(maxh=40.0)))
    bad = validate(MeshOptions(maxh=1.0, minh=2.0))
    @test !isvalid(bad)
    @test any(d -> d.severity == :error, bad.diagnostics)

    # readiness(geom, MeshingTarget) delegates to meshability
    mt = readiness(geom, Delone.MeshingTarget(options=MeshOptions(maxh=40.0)))
    @test mt isa Delone.MeshabilityReport
    @test mt.likely_meshable == true
    @test_throws ArgumentError readiness(geom, Delone.MeshingTarget())  # no options

    m = generate_mesh(geom; maxh=40.0)

    # report(mesh) -> MeshReport
    @test report(m) isa MeshReport
    # readiness(mesh, OodiImportTarget) -> OodiSnapshotReadiness
    @test readiness(m, OodiImportTarget()) isa OodiSnapshotReadiness

    # hierarchy report + readiness
    h = mesh_hierarchy(geom; maxh=40.0, levels=1)
    refine!(h; mode=:uniform)
    @test report(h) isa MeshHierarchyReport
    gmg = readiness(h, GeometricMultigridTarget())
    @test gmg isa ReadinessReport
    @test gmg.subject == :geometric_multigrid
    @test isready(gmg)
    @test readiness(h, OodiImportTarget()).ready

    # single-level hierarchy is not GMG-ready
    h1 = mesh_hierarchy(geom; maxh=40.0, levels=1)
    @test !readiness(h1, GeometricMultigridTarget()).ready

    # generation-result report is the result itself
    res = generate_mesh(geom; maxh=40.0, result=true)
    @test report(res) === res
end

@testset "to_namedtuple serialization (no raw handles)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)

    nt = to_namedtuple(report(m))
    @test nt isa NamedTuple
    @test nt.validation.valid
    @test nt.quality.min_quality isa Real

    ntr = to_namedtuple(generate_mesh(geom; maxh=40.0, result=true))
    @test ntr.success
    @test ntr.has_mesh
    @test ntr.node_count > 0
    @test !haskey(ntr, :mesh)  # raw handle never serialized

    nto = to_namedtuple(MeshOptions(maxh=40.0, grading=0.3))
    @test nto.maxh == 40.0
    @test nto.grading == 0.3

    # readiness reports serialize too
    nrd = to_namedtuple(readiness(m, OodiImportTarget()))
    @test haskey(nrd, :ready)
end
