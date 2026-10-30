// "Expand *": on the * of a SELECT *, replaces it with the columns it stands for, as SQL Prompt
// does in SSMS. Each column gets its table's alias (c.Id), or its name through a join of tables
// without one, and o.* gets o's columns, each with o.
//
// ScriptDom finds the * and what its FROM reads from. SQL Server's
// sys.dm_exec_describe_first_result_set gives the columns of a SELECT that has only that FROM
// (and the statement's CTEs), one marker column ahead of each table's: so views, subqueries,
// CTEs and APPLY expand as the server itself would, and WHERE's @variables, left out, need no
// DECLARE. A FROM reading a #temp table or a @table variable can't be described.
using SqlServerAssist.TSql;

namespace SqlServerAssist.CodeActions;

public sealed class ExpandStar : ICodeAction
{
    const string Marker = "__sql_assist_star_";
    // Wider than this, the columns go one per line, under the first, and what followed the *
    // (FROM...) on a line of its own
    const int MaxWidth = 100;

    public string Id => "sqlserver.expandStar";
    public string Title => "Expand *";
    public string Kind => "refactor.rewrite";

    // On a select list's *, even one that can't be expanded: Resolve then says why
    public bool Offers(FeatureContext context)
    {
        try
        {
            return Parsing.StarAt(context.Document.Text, context.Offset) != null;
        }
        catch (InvalidOperationException)
        {
            return true;
        }
    }

    public async Task<TextEdit[]> Resolve(FeatureContext context, CancellationToken cancellation)
    {
        var connection = context.ConnectionString
            ?? throw new FeatureException("the document has no SQL Server connection to read the columns from");
        Star? star;
        try
        {
            star = Parsing.StarAt(context.Document.Text, context.Offset);
        }
        catch (InvalidOperationException e)
        {
            throw new FeatureException(e.Message);
        }
        if (star == null) throw new FeatureException("the cursor is not on the * of a select list");

        var columns = await Describe(connection, star, cancellation);
        var quoted = Parsing.Quote(columns.SelectMany(c => c));
        return new[] { Edit(context.Document, star, SelectList(star, columns, quoted)) };
    }

    // The SQL of the probe: the * as one marker plus `x.*` per table, over its FROM alone
    static string Probe(Star star)
    {
        var items = star.Qualifier != null ? new[] { $"0 AS [{Marker}0], {star.Qualifier}.*" }
            : star.Sources.Count == 1 ? new[] { $"0 AS [{Marker}0], *" }
            : star.Sources.Select((source, i) => $"0 AS [{Marker}{i}], {source}.*").ToArray();
        return (star.With != null ? star.With + " " : "") + "SELECT " + string.Join(", ", items) + " " + star.From;
    }

    // One list of names per table of the *
    static async Task<List<List<string>>> Describe(string connection, Star star, CancellationToken cancellation)
    {
        const string query = "SELECT ISNULL(name, ''), ISNULL(error_message, '')"
            + " FROM sys.dm_exec_describe_first_result_set(@tsql, NULL, 0) ORDER BY column_ordinal";
        var rows = (await Connections.Query(connection, query, new Dictionary<string, object> { ["@tsql"] = Probe(star) }, cancellation))[0];
        var columns = new List<List<string>>();
        foreach (var (name, error) in rows.Select(r => (r[0], r[1])))
        {
            if (error != "") throw new FeatureException(error);
            if (System.Text.RegularExpressions.Regex.IsMatch(name, "^" + Marker + @"\d+$")) columns.Add(new());
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
