const TEST_FIXTURE_ROOT = joinpath(@__DIR__, "fixtures")
const TEST_SST_CONFIG_DIR = joinpath(TEST_FIXTURE_ROOT, "SSTconfig")
const TEST_SST_TESTS_DIR = joinpath(TEST_FIXTURE_ROOT, "tests")
const TEST_SST_EXAMPLES_DIR = joinpath(TEST_FIXTURE_ROOT, "examples")

function load_test_config!(; reset::Bool=true)
    SemanticSpacetime.load_config!(TEST_SST_CONFIG_DIR; reset=reset)
    return nothing
end
