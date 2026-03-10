@testset "Session Tracking" begin
    SemanticSpacetime.reset_session_tracking!()

    @testset "update and get last saw section" begin
        store = MemoryStore()

        # Track a section
        update_last_saw_section!(store, "chapter1")
        sections = get_last_saw_section(store)
        @test length(sections) == 1
        @test sections[1].section == "chapter1"
        @test sections[1].freq == 1

        # Track again — frequency should increase
        sleep(0.01)
        update_last_saw_section!(store, "chapter1")
        sections = get_last_saw_section(store)
        @test length(sections) == 1
        @test sections[1].freq == 2

        # Track a different section
        update_last_saw_section!(store, "chapter2")
        sections = get_last_saw_section(store)
        @test length(sections) == 2
    end

    @testset "update and get last saw nptr" begin
        SemanticSpacetime.reset_session_tracking!()
        store = MemoryStore()

        nptr = NodePtr(1, 42)
        update_last_saw_nptr!(store, nptr, "test node")

        ls = get_last_saw_nptr(store, nptr)
        @test ls.section == "test node"
        @test ls.freq == 1
        @test ls.nptr == nptr

        # Update again
        sleep(0.01)
        update_last_saw_nptr!(store, nptr, "test node")
        ls = get_last_saw_nptr(store, nptr)
        @test ls.freq == 2

        # Unknown nptr
        ls2 = get_last_saw_nptr(store, NodePtr(99, 99))
        @test ls2.freq == 0
    end

    @testset "get_newly_seen_nptrs" begin
        SemanticSpacetime.reset_session_tracking!()
        store = MemoryStore()

        nptr1 = NodePtr(1, 1)
        nptr2 = NodePtr(2, 2)
        update_last_saw_nptr!(store, nptr1, "node1")
        update_last_saw_nptr!(store, nptr2, "node2")

        # With large horizon, should get all
        recent = get_newly_seen_nptrs(store, 24)
        @test nptr1 in recent
        @test nptr2 in recent

        # With horizon <= 0, get all
        all_seen = get_newly_seen_nptrs(store, 0)
        @test length(all_seen) == 2
    end
end
