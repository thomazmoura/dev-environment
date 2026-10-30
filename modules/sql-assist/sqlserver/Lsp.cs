// The parts of the LSP types the server uses (https://microsoft.github.io/language-server-protocol/).
// Positions are LSP's default UTF-16 code units, which are C# string indices.
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SqlServerAssist;

static class Lsp
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };
}

public record Position(int Line, int Character);
public record Range(Position Start, Position End);

public record TextDocumentIdentifier(string Uri);
public record VersionedTextDocumentIdentifier(string Uri, int Version);
public record TextDocumentItem(string Uri, string LanguageId, int Version, string Text);
public record TextDocumentContentChange(string Text, Range? Range);

public record DidOpenTextDocumentParams(TextDocumentItem TextDocument);
public record DidChangeTextDocumentParams(VersionedTextDocumentIdentifier TextDocument, TextDocumentContentChange[] ContentChanges);
public record DidCloseTextDocumentParams(TextDocumentIdentifier TextDocument);

public record TextEdit(Range Range, string NewText);
public record TextDocumentEdit(VersionedTextDocumentIdentifier TextDocument, TextEdit[] Edits);
public record WorkspaceEdit(TextDocumentEdit[] DocumentChanges);

public record CodeActionParams(TextDocumentIdentifier TextDocument, Range Range);
// What codeAction/resolve needs to find the action and its place again
public record CodeActionData(string Id, string Uri, int Version, Position Position);
public record CodeAction(string Title, string Kind, CodeActionData Data, WorkspaceEdit? Edit = null);

public record CompletionParams(TextDocumentIdentifier TextDocument, Position Position);
public record CompletionItemLabelDetails(string? Description);
public record CompletionItem(
    string Label, int Kind, TextEdit TextEdit, string? SortText = null, string? FilterText = null,
    CompletionItemLabelDetails? LabelDetails = null, string? Documentation = null);
public record CompletionList(bool IsIncomplete, CompletionItem[] Items);

// window/showMessage
public record ShowMessageParams(int Type, string Message);

static class CompletionItemKind
{
    public const int Field = 5;
    public const int Reference = 18;
}

static class MessageType
{
    public const int Error = 1;
    public const int Warning = 2;
}

// sqlserver/connection: the document's connection string, null for none
public record ConnectionParams(TextDocumentIdentifier TextDocument, string? ConnectionString);
// sqlserver/statements
public record StatementsParams(TextDocumentIdentifier TextDocument, Position Position);
