// "Toggle ;" ends the statement under the cursor with a ;, or takes its ; away, and "Toggle ;
// in all statements" does it to the whole document: a ; to each statement missing one, else
// none left. The statements are <Leader>r's (Parsing.Statements, picked as it picks them), so
// one that doesn't parse is toggled too.
//
// T-SQL needs no ; between statements, but a MERGE must end with one, and so must the
// statement before a WITH (a CTE, XMLNAMESPACES) or a THROW: those stay.
using System.Text.RegularExpressions;
using SqlServerAssist.TSql;

namespace SqlServerAssist.CodeActions;

public sealed class ToggleSemicolon : ICodeAction
{
    public string Id => "sqlserver.toggleSemicolon";
    public string Title => "Toggle ;";
    public string Kind => "refactor.rewrite";

    public bool Offers(FeatureContext context) => Find(context) != null;

    public Task<TextEdit[]> Resolve(FeatureContext context, CancellationToken cancellation)
    {
        var (statement, next) = Find(context) ?? throw new FeatureException("there is no statement at the cursor");
        var text = context.Document.Text;
        if (!Semicolons.Ends(text, statement))
            return Task.FromResult(new[] { Semicolons.Add(context.Document, statement) });
        if (Semicolons.Required(text, statement, next) is { } why) throw new FeatureException(why);
        return Task.FromResult(new[] { Semicolons.Remove(context.Document, statement) });
    }

    // The statement under the cursor, in its batch, and the one after it there (null for the last)
    static ((int Start, int End) Statement, (int Start, int End)? Next)? Find(FeatureContext context)
    {
        var document = context.Document;
        var statements = Parsing.Batches(document.Text).Last(b => b.Start <= context.Offset).Statements;
        if (Parsing.Pick(statements, context.Offset, document.Line(document.Position(context.Offset).Line)) is not { } statement)
            return null;
        int i = statements.IndexOf(statement);
        return (statement, i + 1 < statements.Count ? statements[i + 1] : null);
    }
}

public sealed class ToggleAllSemicolons : ICodeAction
{
    public string Id => "sqlserver.toggleAllSemicolons";
    public string Title => "Toggle ; in all statements";
    public string Kind => "source";

    public bool Offers(FeatureContext context) => Parsing.Batches(context.Document.Text).Any(b => b.Statements.Count > 0);

    public Task<TextEdit[]> Resolve(FeatureContext context, CancellationToken cancellation)
    {
        var document = context.Document;
        var batches = Parsing.Batches(document.Text);
        var missing = batches.SelectMany(b => b.Statements).Where(s => !Semicolons.Ends(document.Text, s)).ToList();
        if (missing.Count > 0) return Task.FromResult(missing.Select(s => Semicolons.Add(document, s)).ToArray());

        var removed = batches.SelectMany(b => b.Statements.Where((s, i) =>
                Semicolons.Required(document.Text, s, i + 1 < b.Statements.Count ? b.Statements[i + 1] : null) == null))
            .Select(s => Semicolons.Remove(document, s)).ToArray();
        if (removed.Length == 0) throw new FeatureException("every ; is required: a MERGE's, or before a WITH or THROW");
        return Task.FromResult(removed);
    }
}

static class Semicolons
{
    // The words a statement starts with when the one before it must end with ;
    static readonly Regex LeadsWithTerminated = new(@"\G(WITH|THROW)\b", RegexOptions.IgnoreCase);

    // ScriptDom's statements end with their ;, even one on a line of its own
    public static bool Ends(string text, (int Start, int End) statement) => text[statement.End - 1] == ';';

    // Why the statement's ; can't go, or null when it can
    public static string? Required(string text, (int Start, int End) statement, (int Start, int End)? next)
    {
        if (next is { } n && LeadsWithTerminated.Match(text, n.Start) is { Success: true } m)
            return $"the statement before a {m.Value.ToUpperInvariant()} must end with ;";
        if (Parsing.IsMerge(text[statement.Start..statement.End])) return "a MERGE must end with ;";
        return null;
    }

    public static TextEdit Add(Document document, (int Start, int End) statement) =>
        new(document.Range(statement.End, statement.End), ";");

    // The ; and the blanks before it on its line, or its whole line when it is alone there
    public static TextEdit Remove(Document document, (int Start, int End) statement)
    {
        var text = document.Text;
        int end = statement.End, start = end - 1;
        while (start > statement.Start && text[start - 1] is ' ' or '\t') start--;
        int lineEnd = end;
        while (lineEnd < text.Length && text[lineEnd] is ' ' or '\t') lineEnd++;
        if (start > statement.Start && text[start - 1] == '\n' && (lineEnd == text.Length || text[lineEnd] is '\r' or '\n'))
        {
            // From the end of the line before, so the line break left is the ;'s own
            start--;
            if (text[start - 1] == '\r') start--;
            end = lineEnd;
        }
        return new TextEdit(document.Range(start, end), "");
    }
}
