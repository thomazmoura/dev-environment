// The connection string of each document (sqlserver/connection) and the queries over it.
//
// A connection string holds a password: it stays in this process's memory only, is never
// written to stderr, a log or a message (SqlClient's errors don't include it), and is
// dropped with its document. Persist Security Info stays off, so an open connection no
// longer shows it.
using Microsoft.Data.SqlClient;

namespace SqlServerAssist;

public sealed class Connections
{
    // How long the server may take to answer a query, in seconds
    const int Timeout = 30;

    readonly Dictionary<string, string> byUri = new();
    // connection string → what was read once per connection, by key (see Cached)
    readonly Dictionary<string, Dictionary<string, Task<object>>> cache = new();

    public void Set(string uri, string? connectionString)
    {
        if (string.IsNullOrEmpty(connectionString))
        {
            byUri.Remove(uri);
            return;
        }
        var builder = new SqlConnectionStringBuilder(connectionString) { PersistSecurityInfo = false };
        byUri[uri] = builder.ConnectionString;
    }

    public void Close(string uri) => byUri.Remove(uri);

    public string? For(string uri) => byUri.TryGetValue(uri, out var connectionString) ? connectionString : null;

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

    // What load reads, once per connection and key (as the foreign keys); a failure is read
    // again on the next call
    public async Task<T> Cached<T>(string connectionString, string key, Func<Task<T>> load) where T : class
    {
        if (!cache.TryGetValue(connectionString, out var entries)) cache[connectionString] = entries = new();
        if (!entries.TryGetValue(key, out var task))
        {
            entries[key] = task = Load();
            async Task<object> Load() => await load();
        }
        try
        {
            return (T)await task;
        }
        catch
        {
            if (entries.TryGetValue(key, out var current) && current == task) entries.Remove(key);
            throw;
        }
    }
}
