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

    @testset "check_existing (exact match only)" begin
        nd = new_node_directory()
        n1 = Node("Hello", "ch1")
        append_text_to_directory!(nd, n1)

        # Exact match
        n2 = Node("Hello", "ch2")
        cptr, found = check_existing(nd, n2)
        @test found
        @test cptr == 1

        # Alternative capitalization is now a DISTINCT node (not merged) —
        # variants get linked as NEAR via check_alt_caps! instead.
        n3 = Node("hello", "ch3")
        _, found2 = check_existing(nd, n3)
        @test !found2

        # Backwards-compatible alias points at the same exact-match function
        _, found2b = check_existing_or_alt_caps(nd, n3)
        @test !found2b

        # Not found
        n4 = Node("World", "ch4")
        _, found3 = check_existing(nd, n4)
        @test !found3
    end

    @testset "different_caps and check_alt_caps! (NEAR linking)" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()
        add_mandatory_arrows!()

        nd = new_node_directory()
        p1 = append_text_to_directory!(nd, Node("Hello", "ch1"))
        p2 = append_text_to_directory!(nd, Node("hello", "ch2"))
        # Distinct nodes
        @test p1 != p2

        @test different_caps(Node("Hello"), Node("hello"))
        @test !different_caps(Node("Hello"), Node("Hello"))
        @test !different_caps(Node("Hello"), Node("Goodbye"))

        complete_caps_inferences!(nd)

        # Both variants should now carry a NEAR "caps" link to each other
        caps_arr = get_arrow_by_name("caps").ptr
        near_idx = SemanticSpacetime.sttype_to_index(Int(NEAR))
        n1 = get_memory_node_from_ptr(nd, p1)
        n2 = get_memory_node_from_ptr(nd, p2)
        @test any(l -> l.arr == caps_arr && l.dst == p2, n1.incidence[near_idx])
        @test any(l -> l.arr == caps_arr && l.dst == p1, n2.incidence[near_idx])
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
