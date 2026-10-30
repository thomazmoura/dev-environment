// sqlserver-assist's entry point: LSP over stdin/stdout (Server.cs).
//
// The clients send database passwords (sqlserver/connection), so before reading any message
// the process is closed to other processes running as the same user (Hardening.cs).
using StreamJsonRpc;
using SqlServerAssist;

Hardening.Apply(args);

var formatter = new SystemTextJsonFormatter { JsonSerializerOptions = Lsp.JsonOptions };
var handler = new HeaderDelimitedMessageHandler(Console.OpenStandardOutput(), Console.OpenStandardInput(), formatter);
var rpc = new JsonRpc(handler)
{
    // One message at a time, in order, so a didChange is in before the requests after it.
    // A request awaiting the database lets the next ones through meanwhile
    SynchronizationContext = new Microsoft.VisualStudio.Threading.NonConcurrentSynchronizationContext(sticky: false),
};
var server = new Server(rpc);
rpc.AddLocalRpcTarget(server, new JsonRpcTargetOptions { UseSingleObjectParameterDeserialization = true });
rpc.StartListening();
await rpc.Completion;
return server.ExitCode;
