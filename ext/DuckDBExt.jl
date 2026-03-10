module DuckDBExt

using SemanticSpacetime
import DuckDB
import DBInterface

function SemanticSpacetime.open_duckdb(path::AbstractString=":memory:")
    db = DuckDB.DB(path)
    conn = DuckDB.connect(db)
    return DBStore(conn)
end

end
