#=
Matrix algebra utilities for Semantic Spacetime.

Provides symbolic matrix operations, eigenvector centrality via
power iteration on dense matrices, and gradient field analysis.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Symbol matrix
# ──────────────────────────────────────────────────────────────────

"""
    symbol_matrix(m::Matrix{Float32}) -> Matrix{String}

Convert a numeric adjacency matrix to a symbolic representation.
Non-zero entries become `"r*c"` (row × column indices), zero entries become `""`.
"""
function symbol_matrix(m::Matrix{Float32})::Matrix{String}
    dim = size(m, 1)
    sym = fill("", dim, dim)
    for r in 1:dim
        for c in 1:dim
            if m[r, c] != 0
                sym[r, c] = "$(r)*$(c)"
            end
        end
    end
    return sym
end

# ──────────────────────────────────────────────────────────────────
# Symbolic multiply
# ──────────────────────────────────────────────────────────────────

"""
    symbolic_multiply(m1::Matrix{Float32}, m2::Matrix{Float32},
                      s1::Matrix{String}, s2::Matrix{String}) -> (Matrix{Float32}, Matrix{String})

Multiply numeric matrices and compose symbol matrices for path tracing.
"""
function symbolic_multiply(m1::Matrix{Float32}, m2::Matrix{Float32},
                           s1::Matrix{String}, s2::Matrix{String})
    dim = size(m1, 1)
    result = zeros(Float32, dim, dim)
    sym = fill("", dim, dim)

    for r in 1:dim
        for c in 1:dim
            value = Float32(0)
            symbols = ""
            for j in 1:dim
                if m1[r, j] != 0 && m2[j, c] != 0
                    value += m1[r, j] * m2[j, c]
                    symbols *= "$(s1[r,j])*$(s2[j,c])"
                end
            end
            result[r, c] = value
            sym[r, c] = symbols
        end
    end

    return result, sym
end

# ──────────────────────────────────────────────────────────────────
# Sparse occupancy
# ──────────────────────────────────────────────────────────────────

"""
    get_sparse_occupancy(m::Matrix{Float32}) -> Vector{Int}

Count sum of entries per row (cast to Int).
"""
function get_sparse_occupancy(m::Matrix{Float32})::Vector{Int}
    dim = size(m, 1)
    sparse_count = zeros(Int, dim)
    for r in 1:dim
        for c in 1:dim
            sparse_count[r] += Int(m[r, c])
        end
    end
    return sparse_count
end

# ──────────────────────────────────────────────────────────────────
# Symmetrize matrix
# ──────────────────────────────────────────────────────────────────

"""
    symmetrize_matrix(m::Matrix{Float32}) -> Matrix{Float32}

Return `(m + m') / 2` — but following the Go convention of `m[r,c] + m[c,r]`
(without the division by 2).
"""
function symmetrize_matrix(m::Matrix{Float32})::Matrix{Float32}
    dim = size(m, 1)
    symm = zeros(Float32, dim, dim)
    for r in 1:dim
        for c in r:dim
            v = m[r, c] + m[c, r]
            symm[r, c] = v
            symm[c, r] = v
        end
    end
    return symm
end

# ──────────────────────────────────────────────────────────────────
# Transpose matrix
# ──────────────────────────────────────────────────────────────────

"""
    transpose_matrix(m::Matrix{Float32}) -> Matrix{Float32}

Transpose a matrix. Wraps Julia's `permutedims` for API compatibility.
"""
function transpose_matrix(m::Matrix{Float32})::Matrix{Float32}
    return permutedims(m)
end

# ──────────────────────────────────────────────────────────────────
# Init vector
# ──────────────────────────────────────────────────────────────────

"""
    make_init_vector(dim::Int, init_value::Float32) -> Vector{Float32}

Create a vector of length `dim` filled with `init_value`.
"""
function make_init_vector(dim::Int, init_value::Float32)::Vector{Float32}
    return fill(init_value, dim)
end

# ──────────────────────────────────────────────────────────────────
# Matrix-vector multiplication
# ──────────────────────────────────────────────────────────────────

"""
    matrix_op_vector(m::Matrix{Float32}, v::Vector{Float32}) -> Vector{Float32}

Compute `m * v`.
"""
function matrix_op_vector(m::Matrix{Float32}, v::Vector{Float32})::Vector{Float32}
    return m * v
end

# ──────────────────────────────────────────────────────────────────
# Eigenvector centrality (dense matrix, power iteration)
# ──────────────────────────────────────────────────────────────────

"""
    compute_evc(adj::Matrix{Float32}) -> Vector{Float32}

Eigenvector centrality via power iteration on a dense adjacency matrix.
Iterates up to 10 times, normalizing by max value each step.
"""
function compute_evc(adj::Matrix{Float32})::Vector{Float32}
    dim = size(adj, 1)
    dim == 0 && return Float32[]

    v = fill(Float32(1.0), dim)

    for _ in 1:10
        v_new = matrix_op_vector(adj, v)

        maxval = maximum(abs, v_new; init=Float32(0))
        if maxval > 0
            v_new ./= maxval
        end

        if maximum(abs, v_new .- v; init=Float32(0)) < Float32(0.01)
            return v_new
        end
        v = v_new
    end

    maxval = maximum(abs, v; init=Float32(0))
    if maxval > 0
        v ./= maxval
    end
    return v
end

# ──────────────────────────────────────────────────────────────────
# Gradient field analysis
# ──────────────────────────────────────────────────────────────────

"""
    find_gradient_field_top(sadj::Matrix{Float32}, evc::Vector{Float32})
        -> (hilltops::Dict{Int,Vector{Int}}, sources::Vector{Int}, paths::Vector{Vector{Int}})

Find hill tops in the gradient field of eigenvector centrality.
Each node follows gradient ascent to a local maximum; nodes are grouped
by their hilltop into regions.
"""
function find_gradient_field_top(sadj::Matrix{Float32}, evc::Vector{Float32})
    dim = length(evc)

    localtop = Int[]
    paths = Vector{Int}[]
    regions = Dict{Int,Vector{Int}}()

    for index in 1:dim
        ltop, path = get_hill_top(index, sadj, evc)
        if !haskey(regions, ltop)
            regions[ltop] = Int[]
        end
        push!(regions[ltop], index)
        push!(localtop, ltop)
        push!(paths, path)
    end

    return regions, localtop, paths
end

"""
    get_hill_top(index::Int, sadj::Matrix{Float32}, evc::Vector{Float32}) -> (Int, Vector{Int})

Follow gradient ascent from `index` to local maximum in the eigenvector
centrality field. Returns `(top_index, path)`.
"""
function get_hill_top(index::Int, sadj::Matrix{Float32}, evc::Vector{Float32})
    dim = length(evc)
    topnode = index
    visited = Dict{Int,Bool}()
    visited[index] = true
    path = [index]

    while true
        finished = true
        winner = topnode

        for ngh in 1:dim
            if sadj[topnode, ngh] > 0 && !get(visited, ngh, false)
                visited[ngh] = true
                if evc[ngh] > evc[topnode]
                    winner = ngh
                    finished = false
                end
            end
        end

        finished && break
        topnode = winner
        push!(path, topnode)
    end

    return topnode, path
end
