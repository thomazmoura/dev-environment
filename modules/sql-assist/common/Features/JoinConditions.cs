// Completes a join's ON with the conditions of the foreign keys between the table it joins
// and the ones before it, as SQL Prompt does in SSMS: after
//   FROM Orders o INNER JOIN Customers c ON
// the first item is o.CustomerId = c.Id. A space after ON asks for it.
//
// The dialect's parser finds the join and its tables, and its catalog the foreign keys, read
// once per connection. They match by schema and table, never by column name, so views,
// subqueries, CTEs and temporary tables get nothing. A table written without its schema is
// looked for in the dialect's schemas, in order (the login's default schema, the search
// path). Each key is one item, its columns joined by AND; the tables joined last come first.
using System.Text.RegularExpressions;

namespace SqlAssist;

public abstract class JoinConditionsBase : ICompletion
{
    // How far back from the cursor the ON may be (blank lines between them included)
    const int LookBack = 500;

    // ON, then the word being typed after it. ON may end a line above
    static readonly Regex AfterOn = new(@"(?<!" + Words.Word + @")[Oo][Nn]\s+(" + Words.Word + "*)$", RegexOptions.Compiled);

    // A foreign key, its tables as Key(schema, table), its columns as (parent's, referenced's)
    public sealed record ForeignKey(string Name, string Parent, string Referenced, List<(string, string)> Columns, string Description);

    // The schemas a table written without one is looked for in, in order, and the connection's
    // foreign keys
    public sealed class ForeignKeys(List<string> schemas, List<ForeignKey> keys)
    {
        readonly HashSet<string> tables = keys.SelectMany(k => new[] { k.Parent, k.Referenced }).ToHashSet();
        public List<ForeignKey> Keys => keys;

        // The table's key: in the first of the schemas that has a foreign key on it
        public string KeyOf(JoinTable t) => t.Schema != null ? Key(t.Schema, t.Table)
            : schemas.Select(s => Key(s, t.Table)).FirstOrDefault(tables.Contains) ?? Key(schemas.FirstOrDefault() ?? "", t.Table);

        // From rows of (key id, key name, parent schema, table, column, referenced schema, table,
        // column), a key's columns in order
        public static ForeignKeys FromRows(List<string> schemas, IEnumerable<string[]> rows)
        {
            var keys = new List<ForeignKey>();
            var byId = new Dictionary<string, ForeignKey>();
            foreach (var f in rows)
            {
                if (!byId.TryGetValue(f[0], out var key))
                {
                    key = new ForeignKey(f[1], Key(f[2], f[3]), Key(f[5], f[6]), new(), $"{f[2]}.{f[3]} → {f[5]}.{f[6]}");
                    byId[f[0]] = key;
                    keys.Add(key);
                }
                key.Columns.Add((f[4], f[7]));
            }
            return new ForeignKeys(schemas, keys);
        }
    }

    // A condition: the columns as (earlier's, joined's), still unquoted
    sealed record Condition(string Earlier, string Joined, List<(string, string)> Columns, ForeignKey Key);

    public string Name => "Join conditions";
    public IEnumerable<string> TriggerCharacters => new[] { " " };

    // The tables of the join whose ON ends right before cursor, with no condition yet, or null
    protected abstract Join? JoinAt(string text, int cursor);

    // The connection's foreign keys (called once per connection)
    protected abstract Task<ForeignKeys> Load(string connection, CancellationToken cancellation);

    // The column names quoted where the dialect needs it
    protected abstract Task<List<string>> Quote(FeatureContext context, string connection, IEnumerable<string> names, CancellationToken cancellation);

    public async Task<IEnumerable<CompletionItem>> Complete(FeatureContext context, CancellationToken cancellation)
    {
        var text = context.Document.Text;
        int from = Math.Max(0, context.Offset - LookBack);
        var match = AfterOn.Match(text, from, context.Offset - from);
        if (!match.Success || context.ConnectionString is not { } connection) return Array.Empty<CompletionItem>();
        int start = match.Groups[1].Index;

        // The text with the word after ON taken out
        var join = JoinAt(text.Remove(start, context.Offset - start), start);
        if (join == null || join.Earlier.Count == 0) return Array.Empty<CompletionItem>();
        var keys = await context.Connections.Cached(connection, "foreign keys", () => Load(connection, cancellation));
        var found = Conditions(join, keys);
        if (found.Count == 0) return Array.Empty<CompletionItem>();

        var quoted = await Quote(context, connection, found.SelectMany(c => c.Columns.SelectMany(p => new[] { p.Item1, p.Item2 })), cancellation);
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

    // Case-insensitive, as SQL Server's default collations and Postgres's unquoted names are
    public static string Key(string schema, string table) => (schema + "." + table).ToLowerInvariant();

    // The conditions, nearest tables first
    static List<Condition> Conditions(Join join, ForeignKeys keys)
    {
        var found = new List<Condition>();
        foreach (var joined in Enumerable.Reverse(join.Joined))
            foreach (var earlier in Enumerable.Reverse(join.Earlier))
                foreach (var key in keys.Keys)
                {
                    // Both, for a table joined to itself through its own key (e.ManagerId = m.Id, e.Id = m.ManagerId)
                    if (key.Parent == keys.KeyOf(earlier) && key.Referenced == keys.KeyOf(joined))
                        found.Add(new Condition(earlier.Name, joined.Name, key.Columns, key));
                    if (key.Parent == keys.KeyOf(joined) && key.Referenced == keys.KeyOf(earlier))
                        found.Add(new Condition(earlier.Name, joined.Name, key.Columns.Select(c => (c.Item2, c.Item1)).ToList(), key));
                }
        return found;
    }
}
