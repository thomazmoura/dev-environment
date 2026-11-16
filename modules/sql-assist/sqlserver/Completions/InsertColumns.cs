// Insert columns for T-SQL (../../common/Features/InsertColumns.cs): from sys.columns, without
// identity, computed and rowversion columns, which an INSERT can't set. The table is found by
// OBJECT_ID, so #temp tables get nothing.
using SqlAssist.SqlServer.TSql;

namespace SqlAssist.SqlServer.Completions;

public sealed class InsertColumns : InsertColumnsBase
{
    const string Query =
        "SELECT c.name, TYPE_NAME(c.user_type_id) FROM sys.columns c"
        + " WHERE c.object_id = OBJECT_ID(@table) AND c.is_identity = 0 AND c.is_computed = 0"
        + " AND TYPE_NAME(c.system_type_id) <> 'timestamp'"
        + " ORDER BY c.column_id";

    protected override async Task<List<(string Name, string Type)>> Columns(string connection, string table, CancellationToken cancellation)
    {
        var rows = (await SqlServerConnections.Query(connection, Query, new Dictionary<string, object> { ["@table"] = table }, cancellation))[0];
        return rows.Select(r => (r[0], r[1])).ToList();
    }

    protected override Task<List<string>> Quote(FeatureContext context, string connection, IEnumerable<string> names, CancellationToken cancellation) =>
        Task.FromResult(Parsing.Quote(names));
}
