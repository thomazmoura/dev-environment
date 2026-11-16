// Insert columns for Postgres (../../common/Features/InsertColumns.cs): from pg_attribute, as
// format_type names the types, without identity and generated columns and those numbered by
// a sequence (serial: a nextval() default), as the SQL Server one leaves out its identity. The
// table is found by to_regclass, along the search path.
namespace SqlAssist.Postgres.Completions;

public sealed class InsertColumns : InsertColumnsBase
{
    const string Query =
        "SELECT a.attname, format_type(a.atttypid, a.atttypmod) FROM pg_attribute a"
        + " LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum"
        + " WHERE a.attrelid = to_regclass($1) AND a.attnum > 0 AND NOT a.attisdropped"
        + " AND a.attidentity = '' AND a.attgenerated = ''"
        + " AND coalesce(pg_get_expr(d.adbin, d.adrelid), '') NOT LIKE 'nextval(%'"
        + " ORDER BY a.attnum";

    protected override async Task<List<(string Name, string Type)>> Columns(string connection, string table, CancellationToken cancellation) =>
        (await PostgresConnections.Query(connection, Query, new object[] { table }, cancellation)).Select(r => (r[0], r[1])).ToList();

    protected override Task<List<string>> Quote(FeatureContext context, string connection, IEnumerable<string> names, CancellationToken cancellation) =>
        PostgresConnections.Quote(context, connection, names, cancellation);
}
