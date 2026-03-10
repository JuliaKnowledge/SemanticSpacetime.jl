@testset "Node Directory" begin
    SemanticSpacetime.reset_node_directory!()

    @testset "new_node_directory" begin
        nd = new_node_directory()
        @test nd.n1_top == 0
        @test nd.n2_top == 0
        @test nd.n3_top == 0
        @test nd.lt128_top == 0
        @test isempty(nd.n1directory)
    end

    @testset "append_text_to_directory! — 1-gram" begin
        nd = new_node_directory()
        n1 = Node("hello", "ch1")
        ptr1 = append_text_to_directory!(nd, n1)

        @test ptr1.class == N1GRAM
        @test ptr1.cptr == 1
        @test nd.n1_top == 1

        # Idempotent — same text returns same ptr
        n2 = Node("hello", "ch2")
        ptr2 = append_text_to_directory!(nd, n2)
        @test ptr2 == ptr1
        @test nd.n1_top == 1  # no new entry

        # Different text gets new ptr
        n3 = Node("world", "ch1")
        ptr3 = append_text_to_directory!(nd, n3)
        @test ptr3.cptr == 2
        @test nd.n1_top == 2
    end

    @testset "append_text_to_directory! — 2-gram" begin
        nd = new_node_directory()
        n = Node("hello world", "ch1")
        ptr = append_text_to_directory!(nd, n)
        @test ptr.class == N2GRAM
        @test ptr.cptr == 1
    end

    @testset "append_text_to_directory! — 3-gram" begin
        nd = new_node_directory()
        n = Node("one two three", "ch1")
        ptr = append_text_to_directory!(nd, n)
        @test ptr.class == N3GRAM
        @test ptr.cptr == 1
    end

    @testset "append_text_to_directory! — longer strings" begin
        nd = new_node_directory()

        n1 = Node("this is a longer sentence that has many words", "ch1")
        ptr1 = append_text_to_directory!(nd, n1)
        @test ptr1.class == LT128

        n2 = Node(join(fill("word", 100), " "), "ch1")
        ptr2 = append_text_to_directory!(nd, n2)
        @test ptr2.class == LT1024

        n3 = Node(join(fill("word", 300), " "), "ch1")
        ptr3 = append_text_to_directory!(nd, n3)
        @test ptr3.class == GT1024
    end

    @testset "get_node_txt_from_ptr" begin
        nd = new_node_directory()
        n = Node("test node", "ch1")
        ptr = append_text_to_directory!(nd, n)

        @test get_node_txt_from_ptr(nd, ptr) == "test node"
        @test get_node_txt_from_ptr(nd, NodePtr(1, 999)) == ""
    end

    @testset "get_memory_node_from_ptr" begin
        nd = new_node_directory()
        n = Node("fetch me", "ch1")
        ptr = append_text_to_directory!(nd, n)

        retrieved = get_memory_node_from_ptr(nd, ptr)
        @test retrieved.s == "fetch me"
        @test retrieved.chap == "ch1"
    end

    @testset "check_existing_or_alt_caps" begin
        nd = new_node_directory()
        n1 = Node("Hello", "ch1")
        append_text_to_directory!(nd, n1)

        # Exact match
        n2 = Node("Hello", "ch2")
        cptr, found = check_existing_or_alt_caps(nd, n2)
        @test found
        @test cptr == 1

        # Alt caps (should warn and return existing)
        n3 = Node("hello", "ch3")
        cptr2, found2 = check_existing_or_alt_caps(nd, n3)
        @test found2
        @test cptr2 == 1

        # Not found
        n4 = Node("World", "ch4")
        _, found3 = check_existing_or_alt_caps(nd, n4)
        @test !found3
    end

    @testset "idemp_add_chapter_seq_to_node!" begin
        nd = new_node_directory()
        n = Node("seqtest", "")
        ptr = append_text_to_directory!(nd, n)

        SemanticSpacetime.idemp_add_chapter_seq_to_node!(nd, ptr.class, ptr.cptr, "newchap", true)

        updated = get_memory_node_from_ptr(nd, ptr)
        @test updated.chap == "newchap"
        @test updated.seq == true
    end

    SemanticSpacetime.reset_node_directory!()
end
