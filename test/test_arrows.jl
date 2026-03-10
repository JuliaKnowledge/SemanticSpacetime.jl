@testset "Arrows" begin
    # Reset state before tests
    SemanticSpacetime.reset_arrows!()

    @testset "insert_arrow!" begin
        ptr1 = insert_arrow!("LEADSTO", "then", "and then", "+")
        @test ptr1 == 1

        ptr2 = insert_arrow!("CONTAINS", "contains", "contains", "+")
        @test ptr2 == 2

        # Idempotent — same short name returns same ptr
        ptr1b = insert_arrow!("LEADSTO", "then", "and then duplicate", "+")
        @test ptr1b == ptr1
    end

    @testset "get_stindex_by_name" begin
        @test get_stindex_by_name("NEAR", "+") == SemanticSpacetime.sttype_to_index(0)
        @test get_stindex_by_name("LEADSTO", "+") == SemanticSpacetime.sttype_to_index(1)
        @test get_stindex_by_name("LEADSTO", "-") == SemanticSpacetime.sttype_to_index(-1)
        @test get_stindex_by_name("CONTAINS", "+") == SemanticSpacetime.sttype_to_index(2)
        @test get_stindex_by_name("EXPRESS", "-") == SemanticSpacetime.sttype_to_index(-3)

        # Aliases
        @test get_stindex_by_name("NR", "+") == SemanticSpacetime.sttype_to_index(0)
        @test get_stindex_by_name("LT", "+") == SemanticSpacetime.sttype_to_index(1)
        @test get_stindex_by_name("CN", "-") == SemanticSpacetime.sttype_to_index(-2)
        @test get_stindex_by_name("EP", "+") == SemanticSpacetime.sttype_to_index(3)
    end

    @testset "print_stindex" begin
        @test print_stindex(SemanticSpacetime.sttype_to_index(0)) == "NEAR"
        @test print_stindex(SemanticSpacetime.sttype_to_index(1)) == "+LEADSTO"
        @test print_stindex(SemanticSpacetime.sttype_to_index(-2)) == "-CONTAINS"
    end

    @testset "get_arrow_by_name" begin
        SemanticSpacetime.reset_arrows!()
        insert_arrow!("LEADSTO", "then", "and then", "+")

        entry = get_arrow_by_name("then")
        @test !isnothing(entry)
        @test entry.short == "then"
        @test entry.long == "and then"

        entry2 = get_arrow_by_name("and then")
        @test !isnothing(entry2)
        @test entry2.ptr == entry.ptr

        @test isnothing(get_arrow_by_name("nonexistent"))
    end

    @testset "inverse arrows" begin
        SemanticSpacetime.reset_arrows!()
        fwd = insert_arrow!("LEADSTO", "then", "and then", "+")
        bwd = insert_arrow!("LEADSTO", "before", "comes before", "-")
        insert_inverse_arrow!(fwd, bwd)

        @test SemanticSpacetime.get_inverse_arrow(fwd) == bwd
        @test SemanticSpacetime.get_inverse_arrow(bwd) == fwd
        @test isnothing(SemanticSpacetime.get_inverse_arrow(999))
    end

    @testset "get_sttype_from_arrows" begin
        SemanticSpacetime.reset_arrows!()
        a1 = insert_arrow!("LEADSTO", "then", "and then", "+")
        a2 = insert_arrow!("CONTAINS", "has", "contains", "+")
        a3 = insert_arrow!("LEADSTO", "next", "next step", "+")

        types = get_sttype_from_arrows([a1, a2, a3])
        @test length(types) == 2  # LEADSTO and CONTAINS have different stindices
    end

    # Cleanup
    SemanticSpacetime.reset_arrows!()
end
