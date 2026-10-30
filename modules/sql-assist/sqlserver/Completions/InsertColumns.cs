// Completes an INSERT's column list with all the table's columns, as SQL Prompt does in SSMS:
// after
//   INSERT INTO dbo.Orders (
// the item is CustomerId, OrderDate, Total, to accept and then trim. A '(' asks for it.
//
// The columns come from sys.columns over the document's connection, asked on every request so
// they follow the table's changes, in the table's order. Identity, computed and rowversion
// columns are left out, as an INSERT can't set them. The table is found by OBJECT_ID, so
// #temp tables, which live in the client's own session, get nothing.
using System.Text.RegularExpressions;
using SqlServerAssist.TSql;

namespace SqlServerAssist.Completions;

public sealed class InsertColumns : ICompletion
{
    // How many lines above the cursor the INSERT may start
    const int Lines = 20;

    const string Query =
        "SELECT c.name, TYPE_NAME(c.user_type_id) FROM sys.columns c"
        + " WHERE c.object_id = OBJECT_ID(@table) AND c.is_identity = 0 AND c.is_computed = 0"
        + " AND TYPE_NAME(c.system_type_id) <> 'timestamp'"
        + " ORDER BY c.column_id";

    static readonly Regex OpenParenthesis = new(@"\(\s*(" + Completions.Word + "*)$", RegexOptions.Compiled);
    static readonly Regex Insert = new(@"(?<!" + Completions.Word + ")[Ii][Nn][Ss][Ee][Rr][Tt](?!" + Completions.Word + ")", RegexOptions.Compiled);
    static readonly Regex Into = new(@"^\s+[Ii][Nn][Tt][Oo](?!" + Completions.Word + ")", RegexOptions.Compiled);
    static readonly Regex Table = new(@"^\s+(.*?)\s*\(\s*" + Completions.Word + "*$", RegexOptions.Compiled | RegexOptions.Singleline);
    // A part of a table's name as written: dbo, [My Table] or "x"
    static readonly Regex NamePart = new(@"\G(\[[^\]]*\]|""[^""]*""|[A-Za-z0-9_@#$]+)", RegexOptions.Compiled);

    public string Name => "Insert columns";
    public IEnumerable<string> TriggerCharacters => new[] { "(" };

    public async Task<IEnumerable<CompletionItem>> Complete(FeatureContext context, CancellationToken cancellation)
    {
        if (After(context.Document, context.Offset) is not { } after || context.ConnectionString is not { } connection)
            return Array.Empty<CompletionItem>();
        var (table, start) = after;

        var rows = (await Connections.Query(connection, Query, new Dictionary<string, object> { ["@table"] = table }, cancellation))[0];
        if (rows.Count == 0) return Array.Empty<CompletionItem>();
        var quoted = Parsing.Quote(rows.Select(r => r[0]));
        var label = string.Join(", ", quoted);
        var documentation = table + "\n\n" + string.Join("\n", quoted.Select((column, i) => column + " " + rows[i][1]));
        return new[]
        {
            new CompletionItem(label, CompletionItemKind.Field, new TextEdit(context.Document.Range(start, context.Offset), label),
                LabelDetails: new CompletionItemLabelDetails($"{rows.Count} columns"), Documentation: documentation),
        };
    }

    // The table named by the INSERT whose column list is opened right before the cursor, as
    // written, and the offset the word being typed after its '(' starts at, or null when the
    // text before the cursor isn't `INSERT [INTO] <table> (<word>`. It may span lines
    static (string Table, int Start)? After(Document document, int offset)
    {
        var word = OpenParenthesis.Match(document.LineBefore(offset));
        if (!word.Success) return null;
        int line = document.Position(offset).Line;
        int from = document.Offset(new Position(Math.Max(0, line - Lines), 0));
        var text = document.Text[from..offset];

        // After the last INSERT
        var last = Insert.Matches(text).LastOrDefault();
        if (last == null) return null;
        var rest = Into.Replace(text[(last.Index + last.Length)..], "", 1);
        var name = Table.Match(rest);
        if (!name.Success || !IsName(name.Groups[1].Value)) return null;
        return (name.Groups[1].Value, offset - word.Groups[1].Length);
    }

    // Whether text is a table's name as written: parts joined by dots
    static bool IsName(string text)
    {
        int i = 0;
        while (true)
        {
            var part = NamePart.Match(text, i);
            if (!part.Success) return false;
            i += part.Length;
            if (i >= text.Length) return true;
            if (text[i] != '.') return false;
            i++;
        }
    }
}
