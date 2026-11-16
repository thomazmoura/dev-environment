// Join conditions for Postgres (../../common/Features/JoinConditions.cs): Pg/Parsing.cs finds
// the join and its tables, and the foreign keys come from pg_constraint (a partitioned table's
// once, not its partitions' copies). A table without its schema is looked for along the search
// path, as Postgres resolves it.
using SqlAssist.Postgres.Pg;

namespace SqlAssist.Postgres.Completions;

public sealed class JoinConditions : JoinConditionsBase
{
    const string Schemas = "SELECT s FROM unnest(current_schemas(false)) WITH ORDINALITY AS u(s, n) ORDER BY n";

    const string Keys =
        "SELECT c.oid::text, c.conname, pn.nspname, p.relname, pa.attname, rn.nspname, r.relname, ra.attname"
        + " FROM pg_constraint c"
        + " CROSS JOIN LATERAL unnest(c.conkey, c.confkey) WITH ORDINALITY AS k(parent, referenced, n)"
        + " JOIN pg_class p ON p.oid = c.conrelid JOIN pg_namespace pn ON pn.oid = p.relnamespace"
        + " JOIN pg_attribute pa ON pa.attrelid = c.conrelid AND pa.attnum = k.parent"
        + " JOIN pg_class r ON r.oid = c.confrelid JOIN pg_namespace rn ON rn.oid = r.relnamespace"
        + " JOIN pg_attribute ra ON ra.attrelid = c.confrelid AND ra.attnum = k.referenced"
        + " WHERE c.contype = 'f' AND c.conparentid = 0"
        + " ORDER BY c.oid, k.n";

    protected override Join? JoinAt(string text, int cursor) => Parsing.JoinAt(text, cursor);

    protected override async Task<ForeignKeys> Load(string connection, CancellationToken cancellation)
    {
        var schemas = (await PostgresConnections.Query(connection, Schemas, cancellation: cancellation)).Select(r => r[0]).ToList();
        return ForeignKeys.FromRows(schemas, await PostgresConnections.Query(connection, Keys, cancellation: cancellation));
    }

    protected override Task<List<string>> Quote(FeatureContext context, string connection, IEnumerable<string> names, CancellationToken cancellation) =>
        PostgresConnections.Quote(context, connection, names, cancellation);
}
