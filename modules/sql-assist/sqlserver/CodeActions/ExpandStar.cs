// "Expand *" for T-SQL (../../common/Features/ExpandStar.cs): ScriptDom finds the * and what its
// FROM reads from, and SQL Server's sys.dm_exec_describe_first_result_set describes the probe.
// A FROM reading a #temp table or a @table variable can't be described.
using SqlAssist.SqlServer.TSql;

namespace SqlAssist.SqlServer.CodeActions;

public sealed class ExpandStar : ExpandStarBase
{
    public override string Id => "sqlserver.expandStar";
    protected override string Database => "SQL Server";

    protected override Star? StarAt(string text, int offset) => Parsing.StarAt(text, offset);

    protected override async Task<List<string>> Describe(FeatureContext context, string connection, string probe, CancellationToken cancellation)
    {
        const string query = "SELECT ISNULL(name, ''), ISNULL(error_message, '')"
            + " FROM sys.dm_exec_describe_first_result_set(@tsql, NULL, 0) ORDER BY column_ordinal";
        var rows = (await SqlServerConnections.Query(connection, query, new Dictionary<string, object> { ["@tsql"] = probe }, cancellation))[0];
        if (rows.FirstOrDefault(r => r[1] != "") is { } error) throw new FeatureException(error[1]);
        return rows.Select(r => r[0]).ToList();
    }

    protected override Task<List<string>> Quote(FeatureContext context, string connection, IEnumerable<string> names, CancellationToken cancellation) =>
        Task.FromResult(Parsing.Quote(names));
}
