// sqlserver-assist's entry point (../common/Host.cs), with its own methods: sqlserver/connection,
// a SqlClient connection string, and sqlserver/statements, ScriptDom's statements around a
// position (the protocol is in ../README.md).
using StreamJsonRpc;
using SqlAssist;
using SqlAssist.SqlServer;
using SqlAssist.SqlServer.TSql;

var dialect = new Dialect("sqlserver-assist", new SqlServerConnections(),
    SqlAssist.SqlServer.CodeActions.CodeActions.All, SqlAssist.SqlServer.Completions.Completions.All);
return await Host.Run(dialect, server => new SqlServerMethods(server));

sealed class SqlServerMethods(Server server)
{
    [JsonRpcMethod("sqlserver/connection")]
    public void SetConnection(ConnectionParams p) => server.SetConnection(p);

    [JsonRpcMethod("sqlserver/statements")]
    public SqlAssist.Range[] FindStatements(StatementsParams p)
    {
        var document = server.Open(p.TextDocument.Uri);
        return Parsing.Statements(document.Text, document.Offset(p.Position))
            .Select(s => document.Range(s.Start, s.End)).ToArray();
    }
}

// sqlserver/statements
sealed record StatementsParams(TextDocumentIdentifier TextDocument, Position Position);
