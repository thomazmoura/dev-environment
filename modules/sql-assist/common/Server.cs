// The LSP methods every sql-assist server answers (the protocol is in ../README.md): the
// lifecycle, the documents' text, code actions (the dialect's CodeActions) offered then
// resolved, and completion (its Completions). Each dialect adds its own methods (Host.Run):
// its <dialect>/connection calls SetConnection.
using System.Text.Json;
using StreamJsonRpc;

namespace SqlAssist;

public sealed class Server(JsonRpc rpc, Dialect dialect)
{
    // LSP's RequestFailed
    const int RequestFailed = -32803;

    readonly Documents documents = new();
    readonly Connections connections = dialect.Connections;
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
                codeActionKinds = dialect.CodeActions.Select(a => a.Kind).Distinct(),
                resolveProvider = true,
            },
            completionProvider = new
            {
                triggerCharacters = dialect.Completions.SelectMany(c => c.TriggerCharacters).Distinct(),
            },
        },
        serverInfo = new { name = dialect.Name },
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

    // The dialect's <dialect>/connection
    public void SetConnection(ConnectionParams p)
    {
        try
        {
            connections.Set(p.TextDocument.Uri, p.ConnectionString);
        }
        catch (Exception e) when (e is ArgumentException or FormatException)
        {
            // The connection string builders' messages name the keyword or the index, not a value
            connections.Close(p.TextDocument.Uri);
            Show(MessageType.Error, dialect.Name + ": the connection string was refused: " + e.Message);
        }
    }

    [JsonRpcMethod("textDocument/codeAction")]
    public CodeAction[] OfferCodeActions(CodeActionParams p)
    {
        if (documents.Get(p.TextDocument.Uri) is not { } document) return Array.Empty<CodeAction>();
        var context = new FeatureContext(document, document.Offset(p.Range.Start), connections);
        return dialect.CodeActions
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
        var action = dialect.CodeActions.FirstOrDefault(a => a.Id == p.Data.Id)
            ?? throw Failed($"{dialect.Name}: no code action {p.Data.Id}");
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
        foreach (var completion in dialect.Completions)
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

    // The open document, for the dialect's own methods too
    public Document Open(string uri) => documents.Get(uri) ?? throw Failed(dialect.Name + ": the document is not open");

    public static LocalRpcException Failed(string message) => new(message) { ErrorCode = RequestFailed };

    void Show(int type, string message) =>
        _ = rpc.NotifyWithParameterObjectAsync("window/showMessage", new ShowMessageParams(type, message));
}
