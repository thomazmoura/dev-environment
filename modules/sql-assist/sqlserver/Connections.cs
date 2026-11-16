// SqlClient's side of the documents' connections (../common/Connections.cs): the connection
// strings checked by SqlConnectionStringBuilder, and the queries over them.
using Microsoft.Data.SqlClient;

namespace SqlAssist.SqlServer;

public sealed class SqlServerConnections : Connections
{
    protected override string Normalize(string connectionString) =>
        new SqlConnectionStringBuilder(connectionString) { PersistSecurityInfo = false }.ConnectionString;

    // The rows of each result set, every value as a string ('' for NULL)
    public static async Task<List<List<string[]>>> Query(string connectionString, string sql,
        IReadOnlyDictionary<string, object>? parameters = null, CancellationToken cancellation = default)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellation);
        await using var command = new SqlCommand(sql, connection) { CommandTimeout = Timeout };
        foreach (var (name, value) in parameters ?? new Dictionary<string, object>())
            command.Parameters.AddWithValue(name, value);
        await using var reader = await command.ExecuteReaderAsync(cancellation);
        var sets = new List<List<string[]>>();
        do
        {
            var rows = new List<string[]>();
            while (await reader.ReadAsync(cancellation))
            {
                var row = new string[reader.FieldCount];
                for (int i = 0; i < row.Length; i++) row[i] = reader.IsDBNull(i) ? "" : Convert.ToString(reader.GetValue(i)) ?? "";
                rows.Add(row);
            }
            sets.Add(rows);
        } while (await reader.NextResultAsync(cancellation));
        return sets;
    }
}
