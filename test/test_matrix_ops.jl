@testset "Matrix Operations" begin
    @testset "symbol_matrix" begin
        m = Float32[1 0 2; 0 0 0; 3 0 0]
        s = symbol_matrix(m)
        @test s[1, 1] == "1*1"
        @test s[1, 2] == ""
        @test s[1, 3] == "1*3"
        @test s[2, 1] == ""
        @test s[3, 1] == "3*1"
    end

    @testset "symbolic_multiply" begin
        m1 = Float32[1 2; 3 4]
        m2 = Float32[5 6; 7 8]
        s1 = symbol_matrix(m1)
        s2 = symbol_matrix(m2)

        result, sym = symbolic_multiply(m1, m2, s1, s2)

        # Numeric: standard matrix multiply
        @test result[1, 1] ≈ 1*5 + 2*7
        @test result[1, 2] ≈ 1*6 + 2*8
        @test result[2, 1] ≈ 3*5 + 4*7
        @test result[2, 2] ≈ 3*6 + 4*8

        # Symbolic: non-empty for non-zero products
        @test !isempty(sym[1, 1])
        @test !isempty(sym[1, 2])
    end

    @testset "get_sparse_occupancy" begin
        m = Float32[1 0 2; 0 3 0; 4 0 5]
        occ = get_sparse_occupancy(m)
        @test occ[1] == 3  # 1 + 0 + 2
        @test occ[2] == 3  # 0 + 3 + 0
        @test occ[3] == 9  # 4 + 0 + 5
    end

    @testset "symmetrize_matrix" begin
        m = Float32[0 1 0; 0 0 2; 3 0 0]
        s = symmetrize_matrix(m)

        # s[i,j] should equal s[j,i]
        for i in 1:3, j in 1:3
            @test s[i, j] == s[j, i]
        end
        # s[1,2] = m[1,2] + m[2,1] = 1 + 0 = 1
        @test s[1, 2] ≈ 1.0f0
        # s[1,3] = m[1,3] + m[3,1] = 0 + 3 = 3
        @test s[1, 3] ≈ 3.0f0
        # s[2,3] = m[2,3] + m[3,2] = 2 + 0 = 2
        @test s[2, 3] ≈ 2.0f0
    end

    @testset "transpose_matrix" begin
        m = Float32[1 2 3; 4 5 6; 7 8 9]
        mt = transpose_matrix(m)
        @test mt[1, 2] == m[2, 1]
        @test mt[2, 1] == m[1, 2]
        @test mt[3, 1] == m[1, 3]
    end

    @testset "make_init_vector" begin
        v = make_init_vector(5, Float32(3.0))
        @test length(v) == 5
        @test all(x -> x == 3.0f0, v)
    end

    @testset "matrix_op_vector" begin
        m = Float32[1 0; 0 1]
        v = Float32[3.0, 4.0]
        result = matrix_op_vector(m, v)
        @test result ≈ v

        m2 = Float32[2 1; 0 3]
        result2 = matrix_op_vector(m2, v)
        @test result2[1] ≈ 2*3 + 1*4
        @test result2[2] ≈ 0*3 + 3*4
    end

    @testset "compute_evc" begin
        # Simple chain: 1->2->3
        adj = Float32[0 1 0; 0 0 1; 0 0 0]
        evc = compute_evc(adj)
        @test length(evc) == 3

        # Symmetric graph: all connected
        adj2 = Float32[0 1 1; 1 0 1; 1 1 0]
        evc2 = compute_evc(adj2)
        @test length(evc2) == 3
        # All should be roughly equal due to symmetry
        @test maximum(abs, evc2) ≈ 1.0f0 atol=0.1

        # Empty
        evc3 = compute_evc(Float32[;;])
        @test isempty(evc3)
    end

    @testset "find_gradient_field_top" begin
        # 3-node symmetric graph with different EVC values
        sadj = Float32[0 1 0; 1 0 1; 0 1 0]
        evc = Float32[0.5, 1.0, 0.5]

        regions, localtop, paths = find_gradient_field_top(sadj, evc)

        # Node 2 (highest evc) should be a hilltop
        @test 2 in keys(regions)
        # Nodes 1 and 3 should climb to node 2
        @test localtop[1] == 2
        @test localtop[3] == 2
        @test localtop[2] == 2
    end

    @testset "get_hill_top" begin
        sadj = Float32[0 1 0; 1 0 1; 0 1 0]
        evc = Float32[0.3, 0.8, 0.5]

        top, path = get_hill_top(1, sadj, evc)
        @test top == 2  # Should climb to node 2
        @test path[1] == 1
        @test path[end] == 2

        top3, path3 = get_hill_top(3, sadj, evc)
        @test top3 == 2
    end
end
