// postgres-assist's entry point (../common/Host.cs), with its own method: postgres/connection,
// an Npgsql connection string (the protocol is in ../README.md).
using StreamJsonRpc;
using SqlAssist;
using SqlAssist.Postgres;

var dialect = new Dialect("postgres-assist", new PostgresConnections(),
    SqlAssist.Postgres.CodeActions.CodeActions.All, SqlAssist.Postgres.Completions.Completions.All);
return await Host.Run(dialect, server => new PostgresMethods(server));

sealed class PostgresMethods(Server server)
{
    [JsonRpcMethod("postgres/connection")]
    public void SetConnection(ConnectionParams p) => server.SetConnection(p);
}
