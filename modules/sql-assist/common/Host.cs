// The entry point of every sql-assist server (each dialect's Program.cs): LSP over
// stdin/stdout (Server.cs), with the dialect's own methods from extras.
//
// The clients send database passwords (<dialect>/connection), so before reading any message
// the process is closed to other processes running as the same user (Hardening.cs).
using StreamJsonRpc;

namespace SqlAssist;

public static class Host
{
    public static async Task<int> Run(Dialect dialect, Func<Server, object> extras)
    {
        Hardening.Apply(dialect.Name);

        var formatter = new SystemTextJsonFormatter { JsonSerializerOptions = Lsp.JsonOptions };
        var handler = new HeaderDelimitedMessageHandler(Console.OpenStandardOutput(), Console.OpenStandardInput(), formatter);
        var rpc = new JsonRpc(handler)
        {
            // One message at a time, in order, so a didChange is in before the requests after it.
            // A request awaiting the database lets the next ones through meanwhile
            SynchronizationContext = new Microsoft.VisualStudio.Threading.NonConcurrentSynchronizationContext(sticky: false),
        };
        var server = new Server(rpc, dialect);
        var options = new JsonRpcTargetOptions { UseSingleObjectParameterDeserialization = true };
        rpc.AddLocalRpcTarget(server, options);
        rpc.AddLocalRpcTarget(extras(server), options);
        rpc.StartListening();
        await rpc.Completion;
        return server.ExitCode;
    }
}
