// "Expand *" for Postgres (../../common/Features/ExpandStar.cs): Pg/Parsing.cs finds the * and
// what its FROM reads from, and the server describes the probe without running it, as it does
// a prepared statement's columns. A FROM reading a temporary table can't be described: it lives
// in the client's own session.
using SqlAssist.Postgres.Pg;

namespace SqlAssist.Postgres.CodeActions;

public sealed class ExpandStar : ExpandStarBase
{
    public override string Id => "postgres.expandStar";
    protected override string Database => "Postgres";

    protected override Star? StarAt(string text, int offset) => Parsing.StarAt(text, offset);

    protected override Task<List<string>> Describe(FeatureContext context, string connection, string probe, CancellationToken cancellation) =>
        PostgresConnections.Describe(connection, probe, cancellation);

    protected override Task<List<string>> Quote(FeatureContext context, string connection, IEnumerable<string> names, CancellationToken cancellation) =>
        PostgresConnections.Quote(context, connection, names, cancellation);
}
