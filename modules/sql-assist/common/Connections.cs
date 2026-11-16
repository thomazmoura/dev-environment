// The connection string of each document (<dialect>/connection), and what is read once per
// connection. Each dialect's subclass checks the connection strings and runs the queries.
//
// A connection string holds a password: it stays in this process's memory only, is never
// written to stderr, a log or a message (the drivers' errors don't include it), and is
// dropped with its document. Persist Security Info stays off, so an open connection no
// longer shows it.
namespace SqlAssist;

public abstract class Connections
{
    // How long the server may take to answer a query, in seconds
    public const int Timeout = 30;

    readonly Dictionary<string, string> byUri = new();
    // connection string → what was read once per connection, by key (see Cached)
    readonly Dictionary<string, Dictionary<string, Task<object>>> cache = new();

    // The connection string as kept, Persist Security Info off. Throws ArgumentException or
    // FormatException when the driver refuses it, with a message naming no value
    protected abstract string Normalize(string connectionString);

    public void Set(string uri, string? connectionString)
    {
        if (string.IsNullOrEmpty(connectionString))
        {
            byUri.Remove(uri);
            return;
        }
        byUri[uri] = Normalize(connectionString);
    }

    public void Close(string uri) => byUri.Remove(uri);

    public string? For(string uri) => byUri.TryGetValue(uri, out var connectionString) ? connectionString : null;

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
