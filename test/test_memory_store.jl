@testset "MemoryStore" begin
    # Reset global arrow/context state for clean tests
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    # Register some arrows for testing
    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    contains_fwd = insert_arrow!("CONTAINS", "has", "contains element", "+")
    contains_bwd = insert_arrow!("CONTAINS", "in", "element of", "-")
    insert_inverse_arrow!(contains_fwd, contains_bwd)

    near_arr = insert_arrow!("NEAR", "like", "is similar to", "+")

    @testset "construction" begin
        store = MemoryStore()
        @test store isa AbstractSSTStore
        @test node_count(store) == 0
        @test link_count(store) == 0
    end

    @testset "vertex creation and retrieval" begin
        store = MemoryStore()

        n1 = mem_vertex!(store, "hello", "ch1")
        @test n1.s == "hello"
        @test n1.chap == "ch1"
        @test n1.nptr != NO_NODE_PTR
        @test node_count(store) == 1

        n2 = mem_vertex!(store, "world", "ch1")
        @test n2.s == "world"
        @test node_count(store) == 2

        # Retrieve by pointer
        got = mem_get_node(store, n1.nptr)
        @test got !== nothing
        @test got.s == "hello"

        # Retrieve by name
        nodes = mem_get_nodes_by_name(store, "hello")
        @test length(nodes) == 1
        @test nodes[1].s == "hello"

        # Non-existent
        @test mem_get_node(store, NodePtr(1, 9999)) === nothing
        @test isempty(mem_get_nodes_by_name(store, "nonexistent"))
    end

    @testset "idempotent insertion" begin
        store = MemoryStore()

        n1 = mem_vertex!(store, "duplicate", "ch1")
        n2 = mem_vertex!(store, "duplicate", "ch1")

        # Should return same node, not create a second
        @test node_count(store) == 1
        @test n1.nptr == n2.nptr
        @test n1 === n2
    end

    @testset "chapter listing" begin
        store = MemoryStore()
        @test isempty(mem_get_chapters(store))

        mem_vertex!(store, "a", "chapter1")
        mem_vertex!(store, "b", "chapter2")
        mem_vertex!(store, "c", "chapter1")
        mem_vertex!(store, "d", "chapter3")

        chapters = mem_get_chapters(store)
        @test chapters == ["chapter1", "chapter2", "chapter3"]
    end

    @testset "text search" begin
        store = MemoryStore()
        mem_vertex!(store, "Mary had a little lamb", "nursery")
        mem_vertex!(store, "Whose fleece was white as snow", "nursery")
        mem_vertex!(store, "Jack and Jill went up the hill", "nursery")
        mem_vertex!(store, "The lamb was very happy", "nursery")

        results = mem_search_text(store, "lamb")
        @test length(results) == 2
        texts = sort([r.s for r in results])
        @test texts == ["Mary had a little lamb", "The lamb was very happy"]

        # Case insensitive
        results2 = mem_search_text(store, "LAMB")
        @test length(results2) == 2

        # No match
        @test isempty(mem_search_text(store, "zzzzz"))
    end

    @testset "edge creation" begin
        store = MemoryStore()
        n1 = mem_vertex!(store, "Event A", "ch1")
        n2 = mem_vertex!(store, "Event B", "ch1")

        arr_ptr, sttype = mem_edge!(store, n1, "then", n2)
        @test arr_ptr == fwd
        @test sttype == Int(LEADSTO)
        @test link_count(store) > 0

        # Forward link on n1
        fwd_links = n1.incidence[get_arrow_by_ptr(fwd).stindex]
        @test length(fwd_links) == 1
        @test fwd_links[1].dst == n2.nptr
        @test fwd_links[1].arr == fwd

        # Inverse link on n2
        inv_links = n2.incidence[get_arrow_by_ptr(bwd).stindex]
        @test length(inv_links) == 1
        @test inv_links[1].dst == n1.nptr
        @test inv_links[1].arr == bwd
    end

    @testset "idempotent edge insertion" begin
        store = MemoryStore()
        n1 = mem_vertex!(store, "X", "ch1")
        n2 = mem_vertex!(store, "Y", "ch1")

        mem_edge!(store, n1, "then", n2)
        count_before = link_count(store)

        # Insert same edge again
        mem_edge!(store, n1, "then", n2)
        @test link_count(store) == count_before

        # Only one forward link
        fwd_links = n1.incidence[get_arrow_by_ptr(fwd).stindex]
        @test length(fwd_links) == 1
    end

    @testset "edge with context" begin
        SemanticSpacetime.reset_contexts!()
        store = MemoryStore()
        n1 = mem_vertex!(store, "alpha", "ch1")
        n2 = mem_vertex!(store, "beta", "ch1")

        mem_edge!(store, n1, "then", n2, ["science", "physics"])

        fwd_links = n1.incidence[get_arrow_by_ptr(fwd).stindex]
        @test length(fwd_links) == 1
        ctx_ptr = fwd_links[1].ctx
        @test ctx_ptr > 0
        @test get_context(ctx_ptr) == "physics,science"
    end

    @testset "multiple arrow types" begin
        store = MemoryStore()
        container = mem_vertex!(store, "Container", "ch1")
        element = mem_vertex!(store, "Element", "ch1")
        similar_node = mem_vertex!(store, "Similar", "ch1")

        mem_edge!(store, container, "has", element)
        mem_edge!(store, container, "like", similar_node)

        # CONTAINS link
        has_entry = get_arrow_by_name("has")
        has_links = container.incidence[has_entry.stindex]
        @test length(has_links) == 1
        @test has_links[1].dst == element.nptr

        # NEAR link
        like_entry = get_arrow_by_name("like")
        like_links = container.incidence[like_entry.stindex]
        @test length(like_links) == 1
        @test like_links[1].dst == similar_node.nptr
    end

    @testset "unknown arrow errors" begin
        store = MemoryStore()
        n1 = mem_vertex!(store, "a1", "ch1")
        n2 = mem_vertex!(store, "a2", "ch1")
        @test_throws ErrorException mem_edge!(store, n1, "nonexistent_arrow", n2)
    end

    @testset "size class allocation" begin
        store = MemoryStore()

        # Single word → N1GRAM
        n1 = mem_vertex!(store, "word", "ch1")
        @test n1.nptr.class == N1GRAM

        # Two words → N2GRAM
        n2 = mem_vertex!(store, "two words", "ch1")
        @test n2.nptr.class == N2GRAM

        # Three words → N3GRAM
        n3 = mem_vertex!(store, "three nice words", "ch1")
        @test n3.nptr.class == N3GRAM

        # Longer string → LT128
        n4 = mem_vertex!(store, "this is a sentence with more than three words in it", "ch1")
        @test n4.nptr.class == LT128
    end

    @testset "page map entries" begin
        store = MemoryStore()
        @test isempty(store.page_map)
        pm = PageMap()
        pm.chapter = "ch1"
        pm.alias = "test"
        push!(store.page_map, pm)
        @test length(store.page_map) == 1
    end

    # Clean up global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
