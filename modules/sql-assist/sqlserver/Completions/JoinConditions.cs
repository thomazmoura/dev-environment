// Completes a join's ON with the conditions of the foreign keys between the table it joins
// and the ones before it, as SQL Prompt does in SSMS: after
//   FROM Orders o INNER JOIN Customers c ON
// the first item is o.CustomerId = c.Id. A space after ON asks for it.
//
// ScriptDom finds the join and its tables (parsing the unfinished ON with a placeholder
// condition), and the foreign keys come from sys.foreign_keys over the document's connection,
// read once per connection. They match by schema and table, never by column name, so views,
// subqueries, CTEs and #temp tables get nothing. Each key is one item, its columns joined by
// AND; the tables joined last come first.
using System.Text.RegularExpressions;
using SqlServerAssist.TSql;

namespace SqlServerAssist.Completions;

public sealed class JoinConditions : ICompletion
{
    // How far back from the cursor the ON may be (blank lines between them included)
    const int LookBack = 500;

    // ON, then the word being typed after it. ON may end a line above
    static readonly Regex AfterOn = new(@"(?<!" + Completions.Word + @")[Oo][Nn]\s+(" + Completions.Word + "*)$", RegexOptions.Compiled);

    const string Query =
        "SET NOCOUNT ON;"
        + " SELECT SCHEMA_NAME();"
        + " SELECT fk.object_id, fk.name, SCHEMA_NAME(p.schema_id), p.name, pc.name, SCHEMA_NAME(r.schema_id), r.name, rc.name"
        + " FROM sys.foreign_keys fk"
        + " JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id"
        + " JOIN sys.tables p ON p.object_id = fk.parent_object_id"
        + " JOIN sys.columns pc ON pc.object_id = fkc.parent_object_id AND pc.column_id = fkc.parent_column_id"
        + " JOIN sys.tables r ON r.object_id = fk.referenced_object_id"
        + " JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id"
        + " ORDER BY fk.object_id, fkc.constraint_column_id";

    // A foreign key, its tables as Key(schema, table), its columns as (parent's, referenced's)
    sealed record ForeignKey(string Name, string Parent, string Referenced, List<(string, string)> Columns, string Description);
    // The login's default schema, and the connection's foreign keys
    sealed record ForeignKeys(string Schema, List<ForeignKey> Keys);
    // A condition: the columns as (earlier's, joined's), still unquoted
    sealed record Condition(string Earlier, string Joined, List<(string, string)> Columns, ForeignKey Key);

    public string Name => "Join conditions";
    public IEnumerable<string> TriggerCharacters => new[] { " " };

    public async Task<IEnumerable<CompletionItem>> Complete(FeatureContext context, CancellationToken cancellation)
    {
        var text = context.Document.Text;
        int from = Math.Max(0, context.Offset - LookBack);
        var match = AfterOn.Match(text, from, context.Offset - from);
        if (!match.Success || context.ConnectionString is not { } connection) return Array.Empty<CompletionItem>();
        int start = match.Groups[1].Index;

        // The text with the word after ON taken out, for the placeholder condition to go there
        var join = Parsing.JoinAt(text.Remove(start, context.Offset - start), start);
        if (join == null || join.Earlier.Count == 0) return Array.Empty<CompletionItem>();
        var keys = await context.Connections.Cached(connection, "foreign keys", () => Load(connection, cancellation));
        var found = Conditions(join, keys);
        if (found.Count == 0) return Array.Empty<CompletionItem>();

        var quoted = Parsing.Quote(found.SelectMany(c => c.Columns.SelectMany(p => new[] { p.Item1, p.Item2 })));
        var range = context.Document.Range(start, context.Offset);
        var items = new List<CompletionItem>();
        var seen = new HashSet<string>();
        int n = 0;
        foreach (var condition in found)
        {
            var parts = new List<string>();
            foreach (var _ in condition.Columns)
            {
                parts.Add($"{condition.Earlier}.{quoted[n]} = {condition.Joined}.{quoted[n + 1]}");
                n += 2;
            }
            var label = string.Join(" AND ", parts);
            if (!seen.Add(label)) continue;
            items.Add(new CompletionItem(label, CompletionItemKind.Reference, new TextEdit(range, label),
                SortText: items.Count.ToString("D4"),
                LabelDetails: new CompletionItemLabelDetails(condition.Key.Name),
                Documentation: condition.Key.Name + ": " + condition.Key.Description));
        }
        return items;
    }

    static string Key(string schema, string table) => (schema + "." + table).ToLowerInvariant();

    static async Task<ForeignKeys> Load(string connection, CancellationToken cancellation)
    {
        var sets = await Connections.Query(connection, Query, cancellation: cancellation);
        var schema = sets[0].FirstOrDefault()?[0] is { Length: > 0 } s ? s : "dbo";
        var keys = new List<ForeignKey>();
        var byId = new Dictionary<string, ForeignKey>();
        foreach (var f in sets[1])
        {
            if (!byId.TryGetValue(f[0], out var key))
            {
                key = new ForeignKey(f[1], Key(f[2], f[3]), Key(f[5], f[6]), new(), $"{f[2]}.{f[3]} → {f[5]}.{f[6]}");
                byId[f[0]] = key;
                keys.Add(key);
            }
            key.Columns.Add((f[4], f[7]));
        }
        return new ForeignKeys(schema, keys);
    }

    // The conditions, nearest tables first
    static List<Condition> Conditions(Join join, ForeignKeys keys)
    {
        string KeyOf(JoinTable t) => Key(t.Schema ?? keys.Schema, t.Table);
        var found = new List<Condition>();
        foreach (var joined in Enumerable.Reverse(join.Joined))
            foreach (var earlier in Enumerable.Reverse(join.Earlier))
                foreach (var key in keys.Keys)
                {
                    // Both, for a table joined to itself through its own key (e.ManagerId = m.Id, e.Id = m.ManagerId)
                    if (key.Parent == KeyOf(earlier) && key.Referenced == KeyOf(joined))
                        found.Add(new Condition(earlier.Name, joined.Name, key.Columns, key));
                    if (key.Parent == KeyOf(joined) && key.Referenced == KeyOf(earlier))
                        found.Add(new Condition(earlier.Name, joined.Name, key.Columns.Select(c => (c.Item2, c.Item1)).ToList(), key));
                }
        return found;
    }
}
