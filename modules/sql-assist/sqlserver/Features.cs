// What a code action or a completion is (CodeActions/, Completions/), and what it gets to
// work with. Adding one: a class implementing ICodeAction or ICompletion, and a line in
// CodeActions.All or Completions.All. Server.cs builds the capabilities from those lists.
namespace SqlServerAssist;

// The document, the cursor's offset in its text, and the document's connection string (null
// when it has none)
public sealed record FeatureContext(Document Document, int Offset, Connections Connections)
{
    public string? ConnectionString => Connections.For(Document.Uri);
}

// The reason a feature can't do its job, shown to the user as is (prefixed by the feature's
// name). Anything else thrown is shown too, but this one says it was expected
public sealed class FeatureException(string message) : Exception(message);

public interface ICodeAction
{
    // Stable, kept in the action's data between codeAction and codeAction/resolve
    string Id { get; }
    string Title { get; }
    // An LSP CodeActionKind (refactor.rewrite...)
    string Kind { get; }

    // Whether the action applies at the cursor. Called for every code action menu, so it
    // must be quick: the parse only, no database
    bool Offers(FeatureContext context);

    // The edits of the action, once picked: the slow part (the database...) goes here
    Task<TextEdit[]> Resolve(FeatureContext context, CancellationToken cancellation);
}

public interface ICompletion
{
    // Prefixes the messages of its errors
    string Name { get; }
    // The characters that ask for completion besides typing a word
    IEnumerable<string> TriggerCharacters { get; }

    // Called on every completion request: nothing (quickly) where it doesn't apply
    Task<IEnumerable<CompletionItem>> Complete(FeatureContext context, CancellationToken cancellation);
}
