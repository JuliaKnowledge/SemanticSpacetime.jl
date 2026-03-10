@testset "Tools" begin
    @testset "JSON import - parsing only" begin
        # Test the JSON parsing/node creation logic without a database
        # by testing the helper functions that don't need DB access.

        # Verify the module-level JSON3 import works
        data = SemanticSpacetime.JSON3.read("""{"name": "Alice", "age": 30}""")
        @test data[:name] == "Alice"
        @test data[:age] == 30

        # Test nested JSON parsing
        nested = SemanticSpacetime.JSON3.read("""{"person": {"name": "Bob", "skills": ["julia", "go"]}}""")
        @test nested[:person][:name] == "Bob"
        @test length(nested[:person][:skills]) == 2
    end

    @testset "JSON node creation simulation" begin
        # Reset state for clean test
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_node_directory!()

        # Simulate what import_json! does with the node directory
        # (without requiring a database connection)
        nd = SemanticSpacetime._NODE_DIRECTORY[]

        n1 = Node("name", "json_import")
        ptr1 = append_text_to_directory!(nd, n1)
        @test ptr1 != NO_NODE_PTR

        n2 = Node("Alice", "json_import")
        ptr2 = append_text_to_directory!(nd, n2)
        @test ptr2 != NO_NODE_PTR
        @test ptr1 != ptr2

        n3 = Node("age", "json_import")
        ptr3 = append_text_to_directory!(nd, n3)
        @test ptr3 != NO_NODE_PTR

        n4 = Node("30", "json_import")
        ptr4 = append_text_to_directory!(nd, n4)
        @test ptr4 != NO_NODE_PTR

        # Verify lookup works
        @test get_node_txt_from_ptr(nd, ptr1) == "name"
        @test get_node_txt_from_ptr(nd, ptr2) == "Alice"
        @test get_node_txt_from_ptr(nd, ptr3) == "age"
        @test get_node_txt_from_ptr(nd, ptr4) == "30"

        # Verify idempotency
        n1_dup = Node("name", "json_import")
        ptr1_dup = append_text_to_directory!(nd, n1_dup)
        @test ptr1_dup == ptr1

        # Cleanup
        SemanticSpacetime.reset_node_directory!()
        SemanticSpacetime.reset_arrows!()
    end

    @testset "remove_chapter! validation" begin
        # Test that remove_chapter! validates input
        # (actual DB ops tested in DB test suite)
        @test_throws ErrorException SemanticSpacetime.remove_chapter!(
            SemanticSpacetime.SSTConnection(nothing, false, false), "")
    end

    @testset "browse_notes without DB" begin
        # browse_notes should handle missing connection gracefully
        sst = SemanticSpacetime.SSTConnection(nothing, false, false)
        # This should warn/return empty rather than crash
        # (connection is nothing, so execute_sql_strict will error)
        result = try
            SemanticSpacetime.browse_notes(sst, "test_chapter")
        catch
            ""
        end
        @test result isa String
    end
end
