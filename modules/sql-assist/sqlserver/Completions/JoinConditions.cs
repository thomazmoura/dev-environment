// Join conditions for T-SQL (../../common/Features/JoinConditions.cs): ScriptDom finds the join
// and its tables (parsing the unfinished ON with a placeholder condition), and the foreign keys
// come from sys.foreign_keys. A table without its schema is the login's default schema's.
using SqlAssist.SqlServer.TSql;

namespace SqlAssist.SqlServer.Completions;

public sealed class JoinConditions : JoinConditionsBase
{
    const string Query =
        "SET NOCOUNT ON;"
        + " SELECT SCHEMA_NAME();"
        + " SELECT fk.object_id, fk.name, SCHEMA_NAME(p.schema_id), p.name, pc.name, SCHEMA_NAME(r.schema_id), r.name, rc.name"
        + " FROM sys.foreign_keys fk"
        + " JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id"
        + " JOIN sys.tables p ON p.object_id = fk.parent_object_id"
        + " JOIN sys.columns pc ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id"
        + " JOIN sys.tables r ON r.object_id = fk.referenced_object_id"
        + " JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id"
        + " ORDER BY fk.object_id, fkc.constraint_column_id";

    protected override Join? JoinAt(string text, int cursor) => Parsing.JoinAt(text, cursor);

    protected override async Task<ForeignKeys> Load(string connection, CancellationToken cancellation)
    {
        var sets = await SqlServerConnections.Query(connection, Query, cancellation: cancellation);
        var schema = sets[0].FirstOrDefault()?[0] is { Length: > 0 } s ? s : "dbo";
        return ForeignKeys.FromRows(new List<string> { schema }, sets[1]);
    }

    protected override Task<List<string>> Quote(FeatureContext context, string connection, IEnumerable<string> names, CancellationToken cancellation) =>
        Task.FromResult(Parsing.Quote(names));
}
