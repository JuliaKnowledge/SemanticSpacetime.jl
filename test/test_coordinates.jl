@testset "Coordinates" begin
    @testset "relative_orbit" begin
        origin = SemanticSpacetime.Coords(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

        # Place 1 of 4 at R1 radius
        c = relative_orbit(origin, R1, 0, 4)
        @test c.z == origin.z
        @test sqrt(c.x^2 + c.y^2) ≈ R1 atol=1e-10

        # Place at R2 radius
        c2 = relative_orbit(origin, R2, 0, 4)
        @test sqrt(c2.x^2 + c2.y^2) ≈ R2 atol=1e-10

        # Different angular positions should produce different coordinates
        c3 = relative_orbit(origin, R1, 1, 4)
        @test !(c.x ≈ c3.x && c.y ≈ c3.y)

        # Non-origin placement
        off_origin = SemanticSpacetime.Coords(1.0, 2.0, 3.0, 0.0, 0.0, 0.0)
        c4 = relative_orbit(off_origin, R1, 0, 4)
        @test c4.z == 3.0
        dist = sqrt((c4.x - 1.0)^2 + (c4.y - 2.0)^2)
        @test dist ≈ R1 atol=1e-10
    end

    @testset "assign_cone_coordinates" begin
        # Create a simple cone with 2 paths
        n1 = NodePtr(1, 1)
        n2 = NodePtr(1, 2)
        n3 = NodePtr(1, 3)
        n4 = NodePtr(1, 4)

        path1 = [Link(1, 1.0f0, 0, n1), Link(1, 1.0f0, 0, n2), Link(1, 1.0f0, 0, n3)]
        path2 = [Link(1, 1.0f0, 0, n1), Link(1, 1.0f0, 0, n4)]

        cone = [path1, path2]
        coords = assign_cone_coordinates(cone, 1, 1)

        # All unique nodes should have coordinates
        @test haskey(coords, n1)
        @test haskey(coords, n2)
        @test haskey(coords, n3)
        @test haskey(coords, n4)

        # n1 appears at depth 1, n2 and n4 at depth 2, n3 at depth 3
        # Depth increases along Z
        @test coords[n1].z < coords[n3].z  # n1 is earlier than n3
    end

    @testset "assign_story_coordinates" begin
        n1 = NodePtr(1, 10)
        n2 = NodePtr(1, 11)
        n3 = NodePtr(1, 12)
        axis = [Link(1, 1.0f0, 0, n1), Link(1, 1.0f0, 0, n2), Link(1, 1.0f0, 0, n3)]

        coords = assign_story_coordinates(axis, 1, 1)
        @test length(coords) == 3
        @test haskey(coords, n1)
        @test haskey(coords, n2)
        @test haskey(coords, n3)
    end

    @testset "assign_chapter_coordinates" begin
        c1 = assign_chapter_coordinates(1, 10)
        c2 = assign_chapter_coordinates(2, 10)

        # Different chapters should have different coordinates
        @test !(c1.x ≈ c2.x && c1.y ≈ c2.y && c1.z ≈ c2.z)

        # R should be rho = 0.75
        @test c1.r ≈ 0.75
    end

    @testset "assign_context_set_coordinates" begin
        origin = assign_chapter_coordinates(1, 5)
        c1 = assign_context_set_coordinates(origin, 1, 3)
        c2 = assign_context_set_coordinates(origin, 2, 3)

        @test !(c1.x ≈ c2.x && c1.y ≈ c2.y && c1.z ≈ c2.z)

        # Single swimlane case
        cs = assign_context_set_coordinates(origin, 1, 1)
        @test !isnan(cs.x) && !isnan(cs.y) && !isnan(cs.z)
    end

    @testset "assign_fragment_coordinates" begin
        origin = assign_chapter_coordinates(1, 5)
        f1 = assign_fragment_coordinates(origin, 1, 3)
        f2 = assign_fragment_coordinates(origin, 2, 3)

        @test !(f1.x ≈ f2.x && f1.y ≈ f2.y && f1.z ≈ f2.z)
    end

    @testset "assign_page_coordinates" begin
        pm1 = SemanticSpacetime.PageMap("ch1", "", 0, 1,
            [Link(1, 1.0f0, 0, NodePtr(1, 1)), Link(1, 1.0f0, 0, NodePtr(1, 2))])
        pm2 = SemanticSpacetime.PageMap("ch1", "", 0, 2,
            [Link(1, 1.0f0, 0, NodePtr(1, 3))])

        coords = assign_page_coordinates([pm1, pm2])
        @test haskey(coords, NodePtr(1, 1))
        @test haskey(coords, NodePtr(1, 2))
        @test haskey(coords, NodePtr(1, 3))
    end

    @testset "make_coordinate_directory" begin
        unique = [
            [NodePtr(1, 1), NodePtr(1, 2)],
            [NodePtr(1, 3)],
        ]
        xchannels = [2.0, 1.0]

        coords = make_coordinate_directory(xchannels, unique, 2, 1, 1)
        @test length(coords) == 3
        @test haskey(coords, NodePtr(1, 1))
        @test haskey(coords, NodePtr(1, 2))
        @test haskey(coords, NodePtr(1, 3))

        # Two nodes at same depth should have different X
        @test coords[NodePtr(1, 1)].x != coords[NodePtr(1, 2)].x
    end
end
