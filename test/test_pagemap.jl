@testset "PageMap Operations" begin
    # Reset global state for clean tests
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    @testset "upload and get page map" begin
        store = MemoryStore()

        pm1 = SemanticSpacetime.PageMap("chapter1", "alias1", 0, 1,
            [Link(0, 1.0f0, 0, NodePtr(1, 1))])
        pm2 = SemanticSpacetime.PageMap("chapter1", "alias2", 0, 2,
            [Link(0, 1.0f0, 0, NodePtr(1, 2))])
        pm3 = SemanticSpacetime.PageMap("chapter2", "alias3", 0, 1,
            [Link(0, 1.0f0, 0, NodePtr(1, 3))])

        upload_page_map_event!(store, pm1)
        upload_page_map_event!(store, pm2)
        upload_page_map_event!(store, pm3)

        @test length(store.page_map) == 3

        # Get all
        all_pm = get_page_map(store)
        @test length(all_pm) == 3

        # Filter by chapter
        ch1 = get_page_map(store; chapter="chapter1")
        @test length(ch1) == 2
        @test all(pm -> pm.chapter == "chapter1", ch1)

        ch2 = get_page_map(store; chapter="chapter2")
        @test length(ch2) == 1

        # Case insensitive
        ch_upper = get_page_map(store; chapter="Chapter1")
        @test length(ch_upper) == 2

        # No match
        none = get_page_map(store; chapter="nonexistent")
        @test isempty(none)
    end

    @testset "get page map with pagination" begin
        store = MemoryStore()
        for i in 1:70
            pm = SemanticSpacetime.PageMap("ch", "", 0, i,
                [Link(0, 1.0f0, 0, NodePtr(1, i))])
            upload_page_map_event!(store, pm)
        end

        page1 = get_page_map(store; page=1)
        @test length(page1) == 60

        page2 = get_page_map(store; page=2)
        @test length(page2) == 10
    end

    @testset "get_chapters_by_chap_context" begin
        SemanticSpacetime.reset_contexts!()
        store = MemoryStore()

        ctx = register_context!(["science"])

        pm1 = SemanticSpacetime.PageMap("physics", "", ctx, 1,
            [Link(0, 1.0f0, 0, NodePtr(1, 1))])
        pm2 = SemanticSpacetime.PageMap("chemistry", "", ctx, 1,
            [Link(0, 1.0f0, 0, NodePtr(1, 2))])

        upload_page_map_event!(store, pm1)
        upload_page_map_event!(store, pm2)

        # Get all chapters (TableOfContents mode)
        toc = get_chapters_by_chap_context(store; chapter="TableOfContents",
                                            context=["science"])
        @test haskey(toc, "physics") || haskey(toc, "chemistry")

        # Filter by chapter name
        toc2 = get_chapters_by_chap_context(store; chapter="physics",
                                             context=["science"])
        @test haskey(toc2, "physics")
        @test !haskey(toc2, "chemistry")
    end

    @testset "split_chapters" begin
        # Comma without space: splits
        @test split_chapters("a,b,c") == ["a", "b", "c"]

        # Comma with space: does NOT split
        @test split_chapters("hello, world") == ["hello, world"]

        # Mixed
        @test split_chapters("a,b, c") == ["a", "b, c"]

        # Single chapter
        @test split_chapters("single") == ["single"]

        # Empty
        @test split_chapters("") == [""]
    end
end
