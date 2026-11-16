// "Expand *": on the * of a SELECT *, replaces it with the columns it stands for, as SQL Prompt
// does in SSMS. Each column gets its table's alias (c.Id), or its name through a join of tables
// without one, and o.* gets o's columns, each with o.
//
// The dialect's parser finds the * and what its FROM reads from. The server then describes a
// probe, a SELECT with only that FROM (and the statement's CTEs) and one marker column ahead of
// each table's, without running it: so views, subqueries, CTEs and APPLY/LATERAL expand as the
// server itself would, and WHERE's variables or parameters, left out, need no declaring.
namespace SqlAssist;

public abstract class ExpandStarBase : ICodeAction
{
    const string Marker = "__sql_assist_star_";
    // Wider than this, the columns go one per line, under the first, and what followed the *
    // (FROM...) on a line of its own
    const int MaxWidth = 100;

    public abstract string Id { get; }
    public string Title => "Expand *";
    public string Kind => "refactor.rewrite";

    // "SQL Server", "Postgres": the connection a message says the document lacks
    protected abstract string Database { get; }

    // The select list's * holding the cursor, null off one. Throws InvalidOperationException
    // when it is one but can't be expanded, with why
    protected abstract Star? StarAt(string text, int offset);

    // The names of the probe's columns, in order, without running it
    protected abstract Task<List<string>> Describe(FeatureContext context, string connection, string probe, CancellationToken cancellation);

    // The column names quoted where the dialect needs it
    protected abstract Task<List<string>> Quote(FeatureContext context, string connection, IEnumerable<string> names, CancellationToken cancellation);

    // On a select list's *, even one that can't be expanded: Resolve then says why
    public bool Offers(FeatureContext context)
    {
        try
        {
            return StarAt(context.Document.Text, context.Offset) != null;
        }
        catch (InvalidOperationException)
        {
            return true;
        }
    }

    public async Task<TextEdit[]> Resolve(FeatureContext context, CancellationToken cancellation)
    {
        var connection = context.ConnectionString
            ?? throw new FeatureException($"the document has no {Database} connection to read the columns from");
        Star? star;
        try
        {
            star = StarAt(context.Document.Text, context.Offset);
        }
        catch (InvalidOperationException e)
        {
            throw new FeatureException(e.Message);
        }
        if (star == null) throw new FeatureException("the cursor is not on the * of a select list");

        var columns = Split(await Describe(context, connection, Probe(star), cancellation));
        var quoted = await Quote(context, connection, columns.SelectMany(c => c), cancellation);
        return new[] { Edit(context.Document, star, SelectList(star, columns, quoted)) };
    }

    // The SQL of the probe: the * as one marker plus `x.*` per table, over its FROM alone
    static string Probe(Star star)
    {
        var items = star.Qualifier != null ? new[] { $"0 AS {Marker}0, {star.Qualifier}.*" }
            : star.Sources.Count == 1 ? new[] { $"0 AS {Marker}0, *" }
            : star.Sources.Select((source, i) => $"0 AS {Marker}{i}, {source}.*").ToArray();
        return (star.With != null ? star.With + " " : "") + "SELECT " + string.Join(", ", items) + " " + star.From;
    }

    // The probe's columns as one list of names per table of the *
    static List<List<string>> Split(List<string> names)
    {
        var columns = new List<List<string>>();
        foreach (var name in names)
        {
            if (System.Text.RegularExpressions.Regex.IsMatch(name, "^" + Marker + @"\d+$", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) columns.Add(new());
            else if (columns.Count > 0) columns[^1].Add(name);
        }
        if (columns.Count == 0) throw new FeatureException("the server described no columns");
        return columns;
    }

    // The column list replacing the *, given the quoted names
    static List<string> SelectList(Star star, List<List<string>> columns, List<string> quoted)
    {
        var items = new List<string>();
        int n = 0;
        for (int i = 0; i < columns.Count; i++)
        {
            var prefix = star.Qualifier ?? ((star.Sources.Count > 1 || star.Aliased[i]) ? star.Sources[i] : null);
            foreach (var _ in columns[i])
            {
                items.Add(prefix != null ? prefix + "." + quoted[n] : quoted[n]);
                n++;
            }
        }
        return items;
    }

    // The * replaced by the list, on its line, or one per line past MaxWidth
    static TextEdit Edit(Document document, Star star, List<string> items)
    {
        var start = document.Position(star.Start);
        var end = document.Position(star.End);
        var startLine = document.Line(start.Line);
        var endLine = document.Line(end.Line);
        var before = startLine[..start.Character];
        var after = endLine[end.Character..];

        var joined = string.Join(", ", items);
        var replacement = new List<string> { joined };
        if (Width(before + joined + after) > MaxWidth)
        {
            var indent = new string(' ', Width(before));
            replacement = items.Select(item => indent + item + ",").ToList();
            replacement[0] = replacement[0][indent.Length..];
            replacement[^1] = replacement[^1][..^1];
            if (after.Trim() != "")
            {
                replacement.Add(startLine[..(startLine.Length - startLine.TrimStart().Length)] + after.Trim());
                end = end with { Character = endLine.Length };
            }
        }
        return new TextEdit(new Range(start, end), string.Join("\n", replacement));
    }

    // Display columns, tabs to the next multiple of 8
    static int Width(string text)
    {
        int width = 0;
        foreach (var c in text) width = c == '\t' ? (width / 8 + 1) * 8 : width + 1;
        return width;
    }
}
