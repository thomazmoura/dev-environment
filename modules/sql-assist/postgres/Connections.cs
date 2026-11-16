// Npgsql's side of the documents' connections (../common/Connections.cs): the connection
// strings checked by NpgsqlConnectionStringBuilder, the queries over them, and quoting names
// as the server's keywords need.
using System.Data;
using System.Text.RegularExpressions;
using Npgsql;

namespace SqlAssist.Postgres;

public sealed class PostgresConnections : Connections
{
    // A name Postgres reads back as itself unquoted, unless it is a keyword
    static readonly Regex Bare = new("^[a-z_][a-z0-9_$]*$", RegexOptions.Compiled);

    protected override string Normalize(string connectionString) =>
        new NpgsqlConnectionStringBuilder(connectionString) { PersistSecurityInfo = false }.ConnectionString;

    // The rows of the query, every value as a string ('' for NULL). Its parameters are $1, $2...
    public static async Task<List<string[]>> Query(string connectionString, string sql, object[]? parameters = null,
        CancellationToken cancellation = default)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellation);
        await using var command = new NpgsqlCommand(sql, connection) { CommandTimeout = Timeout };
        foreach (var value in parameters ?? Array.Empty<object>()) command.Parameters.Add(new NpgsqlParameter { Value = value });
        await using var reader = await command.ExecuteReaderAsync(cancellation);
        var rows = new List<string[]>();
        while (await reader.ReadAsync(cancellation))
        {
            var row = new string[reader.FieldCount];
            for (int i = 0; i < row.Length; i++) row[i] = reader.IsDBNull(i) ? "" : Convert.ToString(reader.GetValue(i)) ?? "";
            rows.Add(row);
        }
        return rows;
    }

    // The names of the columns the query returns, as the server describes it without running it
    // (only parsed and planned: SchemaOnly), inside a read-only transaction never committed.
    // The server's error, when it can't, is the FeatureException's message
    public static async Task<List<string>> Describe(string connectionString, string sql, CancellationToken cancellation)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellation);
        await using var transaction = await connection.BeginTransactionAsync(cancellation);
        try
        {
            await using (var readOnly = new NpgsqlCommand("SET TRANSACTION READ ONLY", connection, transaction))
                await readOnly.ExecuteNonQueryAsync(cancellation);
            await using var command = new NpgsqlCommand(sql, connection, transaction) { CommandTimeout = Timeout };
            await using var reader = await command.ExecuteReaderAsync(CommandBehavior.SchemaOnly, cancellation);
            return Enumerable.Range(0, reader.FieldCount).Select(reader.GetName).ToList();
        }
        catch (PostgresException e)
        {
            throw new FeatureException(e.MessageText);
        }
        // Never committed: disposing the transaction rolls it back
    }

    // Column names double-quoted where Postgres needs it, as its quote_ident() does: upper
    // case, spaces... and the keywords it reserves, read once per connection
    public static async Task<List<string>> Quote(FeatureContext context, string connectionString, IEnumerable<string> names,
        CancellationToken cancellation)
    {
        var reserved = await context.Connections.Cached(connectionString, "keywords", async () =>
            (await Query(connectionString, "SELECT word FROM pg_get_keywords() WHERE catcode <> 'U'", cancellation: cancellation))
                .Select(r => r[0]).ToHashSet());
        return names.Select(name => Bare.IsMatch(name) && !reserved.Contains(name) ? name : "\"" + name.Replace("\"", "\"\"") + "\"").ToList();
    }
}
