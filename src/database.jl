#=
Database connection and lifecycle management for Semantic Spacetime.

Uses LibPQ.jl for PostgreSQL connectivity. Credentials default to
the SSTorytime standard (user=sstoryline, password=sst_1234, dbname=sstoryline)
and can be overridden via ~/.SSTorytime.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# SSTConnection
# ──────────────────────────────────────────────────────────────────

"""
    SSTConnection

Wraps a PostgreSQL database connection with cached SST state.
Create with `open_sst()`, close with `close_sst(sst)`.
"""
mutable struct SSTConnection
    conn::Union{LibPQ.Connection, Nothing}
    load_arrows::Bool
    configured::Bool
end

# ──────────────────────────────────────────────────────────────────
# Credential management
# ──────────────────────────────────────────────────────────────────

"""
    load_credentials() -> (user, password, dbname)

Load database credentials from `~/.SSTorytime` if it exists,
otherwise return defaults.
"""
function load_credentials()
    user     = "sstoryline"
    password = "sst_1234"
    dbname   = "sstoryline"

    credfile = joinpath(homedir(), CREDENTIALS_FILE)
    if isfile(credfile)
        for line in eachline(credfile)
            stripped = strip(line)
            isempty(stripped) && continue
            startswith(stripped, '#') && continue
            if occursin(':', stripped)
                key, val = split(stripped, ':', limit=2)
                key = strip(key)
                val = strip(val)
                if key == "user"
                    user = val
                elseif key == "passwd" || key == "password"
                    password = val
                elseif key == "dbname"
                    dbname = val
                end
            end
        end
    end

    return user, password, dbname
end

# ──────────────────────────────────────────────────────────────────
# Open / Close
# ──────────────────────────────────────────────────────────────────

"""
    open_sst(; load_arrows::Bool=false, host::String="localhost", port::Int=5432) -> SSTConnection

Open a connection to the SSTorytime PostgreSQL database.
If `load_arrows` is true, arrow and context directories are loaded
from the database on connection.
"""
function open_sst(; load_arrows::Bool=false, host::String="localhost", port::Int=5432)
    user, password, dbname = load_credentials()

    connstr = "host=$host port=$port dbname=$dbname user=$user password=$password"
    conn = LibPQ.Connection(connstr)

    sst = SSTConnection(conn, load_arrows, false)
    configure!(sst)

    return sst
end

"""
    close_sst(sst::SSTConnection)

Close the database connection.
"""
function close_sst(sst::SSTConnection)
    if !isnothing(sst.conn)
        close(sst.conn)
        sst.conn = nothing
    end
    nothing
end

# ──────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────

"""
    configure!(sst::SSTConnection)

Configure the database connection: create types, tables, stored functions,
and optionally load arrows and contexts from existing data.
"""
function configure!(sst::SSTConnection)
    isnothing(sst.conn) && error("SSTConnection is not open")

    # Create types and tables
    create_schema!(sst)

    if sst.load_arrows
        load_arrows_from_db!(sst)
        load_contexts_from_db!(sst)
    end

    sst.configured = true
    nothing
end

"""
    load_arrows_from_db!(sst::SSTConnection)

Load arrow directory and inverse arrow mappings from the database
into the in-memory directory.
"""
function load_arrows_from_db!(sst::SSTConnection)
    result = LibPQ.execute(sst.conn,
        "SELECT STAindex, Long, Short, ArrPtr FROM ArrowDirectory ORDER BY ArrPtr")

    ct = LibPQ.columntable(result)
    for r in 1:(isempty(ct) ? 0 : length(ct[1]))
        stindex = Int(ct[1][r])
        long    = String(ct[2][r])
        short   = String(ct[3][r])
        ptr     = Int(ct[4][r])

        entry = ArrowEntry(stindex, long, short, ptr)

        # Ensure directory is large enough
        while length(_ARROW_DIRECTORY) < ptr
            push!(_ARROW_DIRECTORY, ArrowEntry(0, "", "", 0))
        end
        _ARROW_DIRECTORY[ptr] = entry
        _ARROW_SHORT_DIR[short] = ptr
        _ARROW_LONG_DIR[long] = ptr
        if ptr > _ARROW_DIRECTORY_TOP[]
            _ARROW_DIRECTORY_TOP[] = ptr
        end
    end

    # Load inverses
    result2 = LibPQ.execute(sst.conn,
        "SELECT Plus, Minus FROM ArrowInverses ORDER BY Plus")

    ct2 = LibPQ.columntable(result2)
    for r in 1:(isempty(ct2) ? 0 : length(ct2[1]))
        fwd = Int(ct2[1][r])
        bwd = Int(ct2[2][r])
        _INVERSE_ARROWS[fwd] = bwd
        _INVERSE_ARROWS[bwd] = fwd
    end

    nothing
end

"""
    load_contexts_from_db!(sst::SSTConnection)

Load context directory from the database into the in-memory directory.
"""
function load_contexts_from_db!(sst::SSTConnection)
    result = LibPQ.execute(sst.conn,
        "SELECT Context, CtxPtr FROM ContextDirectory ORDER BY CtxPtr")

    ct = LibPQ.columntable(result)
    for r in 1:(isempty(ct) ? 0 : length(ct[1]))
        ctx = String(ct[1][r])
        ptr = Int(ct[2][r])

        entry = ContextEntry(ctx, ptr)

        while length(_CONTEXT_DIRECTORY) < ptr
            push!(_CONTEXT_DIRECTORY, ContextEntry("", 0))
        end
        _CONTEXT_DIRECTORY[ptr] = entry
        _CONTEXT_DIR[ctx] = ptr
        if ptr > _CONTEXT_TOP[]
            _CONTEXT_TOP[] = ptr
        end
    end

    nothing
end

# ──────────────────────────────────────────────────────────────────
# SQL execution helpers
# ──────────────────────────────────────────────────────────────────

"""
    execute_sql(sst::SSTConnection, sql::AbstractString)

Execute a SQL statement, ignoring errors (for idempotent CREATE operations).
"""
function execute_sql(conn::LibPQ.Connection, sql::AbstractString)
    try
        LibPQ.execute(conn, sql)
    catch e
        # Silently ignore "already exists" type errors
        msg = string(e)
        if !occursin("already exists", msg) && !occursin("duplicate", msg)
            @debug "SQL warning" sql exception=e
        end
    end
    nothing
end

# Accept either an SSTConnection or a raw LibPQ.Connection (callers use both).
execute_sql(sst::SSTConnection, sql::AbstractString) = execute_sql(sst.conn, sql)

"""
    execute_sql_strict(sst::SSTConnection, sql::AbstractString) -> LibPQ.Result
    execute_sql_strict(conn::LibPQ.Connection, sql::AbstractString) -> LibPQ.Result

Execute a SQL statement, propagating errors.
"""
execute_sql_strict(conn::LibPQ.Connection, sql::AbstractString) = LibPQ.execute(conn, sql)
execute_sql_strict(sst::SSTConnection, sql::AbstractString) = execute_sql_strict(sst.conn, sql)
