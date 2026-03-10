@testset "Context" begin
    SemanticSpacetime.reset_contexts!()

    @testset "compile_context_string" begin
        @test compile_context_string(String[]) == ""
        @test compile_context_string(["alpha"]) == "alpha"
        @test compile_context_string(["beta", "alpha"]) == "alpha,beta"
        @test compile_context_string(["c", "a", "b"]) == "a,b,c"
        # Deduplication
        @test compile_context_string(["a", "a", "b"]) == "a,b"
        # Strips whitespace
        @test compile_context_string([" x ", "y "]) == "x,y"
        # Filters empty
        @test compile_context_string(["", "a", ""]) == "a"
    end

    @testset "register_context!" begin
        SemanticSpacetime.reset_contexts!()

        ptr1 = register_context!(["alpha", "beta"])
        @test ptr1 == 1

        ptr2 = register_context!(["gamma"])
        @test ptr2 == 2

        # Idempotent — same labels return same ptr
        ptr3 = register_context!(["beta", "alpha"])
        @test ptr3 == ptr1  # same context, just reordered
    end

    @testset "try_context" begin
        SemanticSpacetime.reset_contexts!()

        # Empty context returns 0
        @test try_context(String[]) == 0
        @test try_context([""]) == 0

        # Auto-registers new context
        ptr = try_context(["hello", "world"])
        @test ptr > 0

        # Returns same ptr for same context
        ptr2 = try_context(["world", "hello"])
        @test ptr2 == ptr
    end

    @testset "get_context" begin
        SemanticSpacetime.reset_contexts!()

        @test get_context(0) == ""
        @test get_context(-1) == ""
        @test get_context(999) == ""

        ptr = register_context!(["foo", "bar"])
        @test get_context(ptr) == "bar,foo"
    end

    @testset "merge_context_lists" begin
        SemanticSpacetime.reset_contexts!()

        ptr = SemanticSpacetime.merge_context_lists(["a", "b"], ["c", "d"])
        @test get_context(ptr) == "a,b,c,d"
    end

    SemanticSpacetime.reset_contexts!()
end
