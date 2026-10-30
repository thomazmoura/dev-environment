// The LSP methods sqlserver-assist answers (the protocol is in ../README.md): the lifecycle,
// the documents' text, code actions (CodeActions.All) offered then resolved, completion
// (Completions.All), and the sqlserver/* methods of its own.
using System.Text.Json;
using StreamJsonRpc;
using SqlServerAssist.CodeActions;
using SqlServerAssist.Completions;
using SqlServerAssist.TSql;

namespace SqlServerAssist;

public sealed class Server(JsonRpc rpc)
{
    // LSP's RequestFailed
    const int RequestFailed = -32803;

    readonly Documents documents = new();
    readonly Connections connections = new();
    bool shutdown;

    public int ExitCode { get; private set; }

    [JsonRpcMethod("initialize")]
    public object Initialize(JsonElement _) => new
    {
        capabilities = new
        {
            positionEncoding = "utf-16",
            // Open/close and the whole text on each change
            textDocumentSync = new { openClose = true, change = 1 },
            codeActionProvider = new
            {
                codeActionKinds = CodeActions.CodeActions.All.Select(a => a.Kind).Distinct(),
                resolveProvider = true,
            },
            completionProvider = new
            {
                triggerCharacters = Completions.Completions.All.SelectMany(c => c.TriggerCharacters).Distinct(),
            },
        },
        serverInfo = new { name = "sqlserver-assist" },
    };

    [JsonRpcMethod("initialized")]
    public void Initialized(JsonElement _) { }

    [JsonRpcMethod("shutdown")]
    public object? Shutdown()
    {
        shutdown = true;
        return null;
    }

    [JsonRpcMethod("exit")]
    public void Exit()
    {
        ExitCode = shutdown ? 0 : 1;
        Environment.Exit(ExitCode);
    }

    [JsonRpcMethod("textDocument/didOpen")]
    public void DidOpen(DidOpenTextDocumentParams p) =>
        documents.Set(p.TextDocument.Uri, p.TextDocument.Version, p.TextDocument.Text);

    [JsonRpcMethod("textDocument/didChange")]
    public void DidChange(DidChangeTextDocumentParams p)
    {
        if (p.ContentChanges.LastOrDefault() is { Range: null } whole)
            documents.Set(p.TextDocument.Uri, p.TextDocument.Version, whole.Text);
    }

    [JsonRpcMethod("textDocument/didClose")]
    public void DidClose(DidCloseTextDocumentParams p)
    {
        documents.Close(p.TextDocument.Uri);
        connections.Close(p.TextDocument.Uri);
    }

    [JsonRpcMethod("sqlserver/connection")]
    public void SetConnection(ConnectionParams p)
    {
        try
        {
            connections.Set(p.TextDocument.Uri, p.ConnectionString);
        }
        catch (Exception e) when (e is ArgumentException or FormatException)
        {
            // SqlConnectionStringBuilder's messages name the keyword or the index, not a value
            connections.Close(p.TextDocument.Uri);
            Show(MessageType.Error, "sqlserver-assist: the connection string was refused: " + e.Message);
        }
    }

    [JsonRpcMethod("sqlserver/statements")]
    public Range[] FindStatements(StatementsParams p)
    {
        var document = Open(p.TextDocument.Uri);
        return Parsing.Statements(document.Text, document.Offset(p.Position))
            .Select(s => document.Range(s.Start, s.End)).ToArray();
    }

    [JsonRpcMethod("textDocument/codeAction")]
    public CodeAction[] OfferCodeActions(CodeActionParams p)
    {
        if (documents.Get(p.TextDocument.Uri) is not { } document) return Array.Empty<CodeAction>();
        var context = new FeatureContext(document, document.Offset(p.Range.Start), connections);
        return CodeActions.CodeActions.All
            .Where(action =>
            {
                try { return action.Offers(context); }
                catch { return false; }
            })
            .Select(action => new CodeAction(action.Title, action.Kind,
                new CodeActionData(action.Id, document.Uri, document.Version, p.Range.Start)))
            .ToArray();
    }

    [JsonRpcMethod("codeAction/resolve")]
    public async Task<CodeAction> ResolveCodeAction(CodeAction p, CancellationToken cancellation)
    {
        var action = CodeActions.CodeActions.All.FirstOrDefault(a => a.Id == p.Data.Id)
            ?? throw Failed($"sqlserver-assist: no code action {p.Data.Id}");
        var document = Open(p.Data.Uri);
        if (document.Version != p.Data.Version) throw Failed($"{action.Title}: the document changed since");
        try
        {
            var edits = await action.Resolve(new FeatureContext(document, document.Offset(p.Data.Position), connections), cancellation);
            var edit = new WorkspaceEdit(new[] { new TextDocumentEdit(new VersionedTextDocumentIdentifier(document.Uri, document.Version), edits) });
            return p with { Edit = edit };
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            throw Failed($"{action.Title}: {e.Message}");
        }
    }

    [JsonRpcMethod("textDocument/completion")]
    public async Task<CompletionList> Complete(CompletionParams p, CancellationToken cancellation)
    {
        var items = new List<CompletionItem>();
        if (documents.Get(p.TextDocument.Uri) is not { } document) return new CompletionList(false, items.ToArray());
        var context = new FeatureContext(document, document.Offset(p.Position), connections);
        foreach (var completion in Completions.Completions.All)
        {
            try
            {
                items.AddRange(await completion.Complete(context, cancellation));
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                Show(MessageType.Warning, $"{completion.Name}: {e.Message}");
            }
        }
        return new CompletionList(false, items.ToArray());
    }

    Document Open(string uri) => documents.Get(uri) ?? throw Failed("sqlserver-assist: the document is not open");

    static LocalRpcException Failed(string message) => new(message) { ErrorCode = RequestFailed };

    void Show(int type, string message) =>
        _ = rpc.NotifyWithParameterObjectAsync("window/showMessage", new ShowMessageParams(type, message));
}
