module SQLiteExt

using SemanticSpacetime
import SQLite
import DBInterface

function SemanticSpacetime.open_sqlite(path::AbstractString=":memory:")
    db = SQLite.DB(path)
    return DBStore(db)
end

end
