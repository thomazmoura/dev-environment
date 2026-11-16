// What postgres-assist reads from a Postgres document, as ../../common/Shapes.cs has it: the
// select list's * under the cursor and what its FROM reads from, and the tables of the join
// whose ON is being written. Offsets are string indices (UTF-16), the end excluded.
//
// Postgres has no parser to call from here (ScriptDom's counterpart, libpg_query, is native
// code), so this reads tokens: psql's own rules for where a statement ends (as NeoVim's
// config/sql_split_postgres.lua cuts them for <Leader>r: a ';' outside strings, quoted names,
// comments, $$ bodies, parentheses and BEGIN ATOMIC ... END), then the clauses of a SELECT by
// their keywords at its parentheses' depth. That is all Expand * and the join conditions
// need: the server itself checks the probe they build.
namespace SqlAssist.Postgres.Pg;

public enum Kind { Word, Quoted, String, Number, Symbol, Dollar, Param }

public readonly record struct Token(Kind Kind, int Start, int End, string Text)
{
    public bool Is(string word) => Kind == Kind.Word && string.Equals(Text, word, StringComparison.OrdinalIgnoreCase);
    public bool IsSymbol(char c) => Kind == Kind.Symbol && Text[0] == c;
    // A name: a word or a "quoted" one
    public bool IsName => Kind is Kind.Word or Kind.Quoted;
    public string Lower => Text.ToLowerInvariant();
}

public static class Parsing
{
    // Where a FROM (and a select list) ends at its SELECT's depth
    static readonly HashSet<string> Clauses = new(StringComparer.OrdinalIgnoreCase)
    {
        "where", "group", "having", "window", "order", "limit", "offset", "fetch", "for",
        "union", "intersect", "except", "returning",
    };
    static readonly HashSet<string> JoinWords = new(StringComparer.OrdinalIgnoreCase)
    {
        "natural", "inner", "left", "right", "full", "outer", "cross", "join",
    };
    // Words after a FROM item that are not its alias
    static readonly HashSet<string> NotAliases = new(Clauses.Concat(JoinWords).Concat(new[] { "on", "using", "tablesample", "with", "lateral" }),
        StringComparer.OrdinalIgnoreCase);

    // An item of a FROM: its first and last token, the name it goes by there as written (null
    // for a subquery without an alias), whether that is an alias, and for a table its schema
    // (null when not written) and name, unquoted
    record Item(int First, int Last, string? Name, bool Aliased, string? Schema, string? Table);

    // The select list's * holding the cursor, null off one. Throws InvalidOperationException
    // when it is one but can't be expanded, with why
    public static Star? StarAt(string text, int cursor)
    {
        if (StatementAt(text, cursor) is not { } t) return null;
        var d = Depths(t);
        for (int s = 0; s < t.Count; s++)
        {
            if (!t[s].IsSymbol('*')) continue;
            // o.* and sales.o.*
            int q = s;
            while (q >= 2 && t[q - 1].IsSymbol('.') && t[q - 2].IsName) q -= 2;
            if (cursor < t[q].Start || cursor >= t[s].End || !InSelectList(t, d, q)) continue;
            return Expand(text, t, d, q, s);
        }
        return null;
    }

    // The tables of the join whose ON ends right before cursor (with nothing after it yet), or null
    public static Join? JoinAt(string text, int cursor)
    {
        if (StatementAt(text, cursor) is not { } statement) return null;
        var t = statement.Where(token => token.End <= cursor).ToList();
        if (t.Count == 0 || !t[^1].Is("on")) return null;
        var d = Depths(t);
        int on = t.Count - 1, depth = d[on];

        // The JOIN of the ON, then where its chain of joins starts: a ',', the FROM or a '('
        int j = on - 1;
        while (j >= 0 && !(d[j] == depth && t[j].Is("join")))
        {
            if (d[j] < depth) return null;
            j--;
        }
        if (j < 0) return null;
        int k = j - 1;
        while (k >= 0 && d[k] >= depth && !(d[k] == depth && (t[k].IsSymbol(',') || t[k].Is("from")))) k--;

        var ctes = With(t, d).Names;
        List<JoinTable> Tables(List<Item> items) => items
            .Where(i => i.Table != null && !(i.Schema == null && ctes.Contains(i.Table)))
            .Select(i => new JoinTable(i.Schema, i.Table!, i.Name!)).ToList();
        return new Join(Tables(FromItems(t, d, j + 1, on)), Tables(FromItems(t, d, k + 1, j)));
    }

    // Whether the * (or its qualifier) at q is an item of a select list: right after SELECT,
    // DISTINCT [ON (...)], ALL or a ',' of one, not count(*) or a * b
    static bool InSelectList(List<Token> t, int[] d, int q)
    {
        int p = q - 1;
        if (p < 0) return false;
        if (t[p].Is("select") || t[p].Is("distinct") || t[p].Is("all")) return true;
        if (t[p].IsSymbol(')'))
        {
            int open = p - 1;
            while (open >= 0 && !(t[open].IsSymbol('(') && d[open] == d[p])) open--;
            return open >= 2 && t[open - 1].Is("on") && t[open - 2].Is("distinct");
        }
        if (!t[p].IsSymbol(',')) return false;
        for (int k = p - 1; k >= 0 && d[k] >= d[q]; k--)
        {
            if (d[k] != d[q] || t[k].Kind != Kind.Word) continue;
            if (t[k].Is("select")) return true;
            if (t[k].Is("from") || t[k].Is("values") || t[k].Is("set") || t[k].Is("by") || Clauses.Contains(t[k].Text)) return false;
        }
        return false;
    }

    // The Star of the * at s (its qualifier from q): its SELECT's FROM, at the same depth
    static Star Expand(string text, List<Token> t, int[] d, int q, int s)
    {
        int depth = d[s];
        string? qualifier = q < s ? text[t[q].Start..t[s - 2].End] : null;

        int from = -1;
        for (int j = s + 1; j < t.Count && d[j] >= depth; j++)
        {
            if (d[j] != depth || t[j].Kind != Kind.Word) continue;
            if (t[j].Is("from")) { from = j; break; }
            if (Clauses.Contains(t[j].Text)) break;
        }
        if (from < 0) throw new InvalidOperationException("the * reads from no FROM");
        int end = from + 1;
        while (end < t.Count && d[end] >= depth && !(d[end] == depth && t[end].Kind == Kind.Word && Clauses.Contains(t[end].Text))) end++;

        var items = FromItems(t, d, from + 1, end);
        if (items.Count == 0) throw new InvalidOperationException("the FROM reads from no table");
        foreach (var item in items.Where(i => i.Name == null))
            throw new InvalidOperationException("a table of the FROM has no name to read its columns by: " + text[t[item.First].Start..t[item.Last].End]);

        var with = With(t, d).End;
        return new Star(t[q].Start, t[s].End, qualifier,
            items.Select(i => i.Name!).ToList(), items.Select(i => i.Aliased).ToList(),
            with >= 0 ? text[t[0].Start..t[with].End] : null, text[t[from].Start..t[end - 1].End]);
    }

    // The items of the FROM list tokens from..to-1 hold, in order, out of their joins and
    // parenthesized joins. ON and USING conditions are skipped
    static List<Item> FromItems(List<Token> t, int[] d, int from, int to)
    {
        var items = new List<Item>();
        if (from >= to) return items;
        int depth = d[from];
        int i = from;
        while (i < to)
        {
            if (d[i] != depth || t[i].IsSymbol(',') || IsJoinWord(t, i)) { i++; continue; }
            if (t[i].Is("on"))
            {
                i++;
                while (i < to && !(d[i] == depth && (t[i].IsSymbol(',') || IsJoinWord(t, i)))) i++;
                continue;
            }
            if (t[i].Is("using"))
            {
                i++;
                if (i < to && t[i].IsSymbol('(')) i = Close(t, d, i) + 1;
                continue;
            }
            i = ReadItem(t, d, i, to, items);
        }
        return items;
    }

    // Reads the FROM item at i into items (several for a parenthesized join), and where it ends
    static int ReadItem(List<Token> t, int[] d, int i, int to, List<Item> items)
    {
        int first = i;
        if (t[i].Is("lateral") || t[i].Is("only")) i++;
        if (i >= to) return i;

        string? name = null, schema = null, table = null;
        List<Item>? nested = null;
        if (t[i].IsSymbol('('))
        {
            // A subquery, or a parenthesized join
            int close = Close(t, d, i);
            var inner = i + 1 < t.Count ? t[i + 1] : default;
            if (!(inner.Is("select") || inner.Is("with") || inner.Is("values") || inner.Is("table")))
                nested = FromItems(t, d, i + 1, Math.Min(close, to));
            i = close + 1;
        }
        else if (t[i].IsName)
        {
            var parts = new List<int> { i };
            while (i + 2 < to && t[i + 1].IsSymbol('.') && t[i + 2].IsName)
            {
                parts.Add(i + 2);
                i += 2;
            }
            i++;
            name = t[parts[^1]].Text;
            if (i < to && t[i].IsSymbol('('))
            {
                // A function: named after it, no table
                i = Close(t, d, i) + 1;
            }
            else
            {
                table = Unquote(t[parts[^1]]);
                schema = parts.Count > 1 ? Unquote(t[parts[^2]]) : null;
            }
            // ONLY t *: the table with its inheritors
            if (i < to && t[i].IsSymbol('*')) i++;
        }
        else
        {
            return i + 1;
        }

        if (i + 1 < to && t[i].Is("with") && t[i + 1].Is("ordinality")) i += 2;
        if (i < to && t[i].Is("tablesample"))
        {
            i++;
            if (i < to && t[i].IsName) i++;
            if (i < to && t[i].IsSymbol('(')) i = Close(t, d, i) + 1;
            if (i < to && t[i].Is("repeatable"))
            {
                i++;
                if (i < to && t[i].IsSymbol('(')) i = Close(t, d, i) + 1;
            }
        }

        string? alias = null;
        if (i < to && t[i].Is("as"))
        {
            i++;
            if (i < to && t[i].IsName) alias = t[i++].Text;
        }
        else if (i < to && (t[i].Kind == Kind.Quoted || (t[i].Kind == Kind.Word && !NotAliases.Contains(t[i].Text))))
        {
            alias = t[i++].Text;
        }
        // Its columns' aliases (or a function's column definitions)
        if (alias != null && i < to && t[i].IsSymbol('(')) i = Close(t, d, i) + 1;

        if (nested != null && alias == null) items.AddRange(nested);
        else items.Add(new Item(first, Math.Min(i, to) - 1, alias ?? name, alias != null, schema, table));
        return i;
    }

    // A join's keyword, not a function called left() or right()
    static bool IsJoinWord(List<Token> t, int i) =>
        t[i].Kind == Kind.Word && JoinWords.Contains(t[i].Text) && !(i + 1 < t.Count && t[i + 1].IsSymbol('('));

    // The statement's WITH: the index of its last CTE's closing ')' (-1 without one) and the
    // CTEs' names, unquoted
    static (int End, HashSet<string> Names) With(List<Token> t, int[] d)
    {
        var names = new HashSet<string>();
        int end = -1;
        if (t.Count == 0 || !t[0].Is("with")) return (end, names);
        int i = 1;
        if (i < t.Count && t[i].Is("recursive")) i++;
        while (i < t.Count && t[i].IsName)
        {
            var name = Unquote(t[i++]);
            if (i < t.Count && t[i].IsSymbol('(')) i = Close(t, d, i) + 1;
            if (!(i < t.Count && t[i].Is("as"))) break;
            i++;
            if (i < t.Count && t[i].Is("not")) i++;
            if (i < t.Count && t[i].Is("materialized")) i++;
            if (!(i < t.Count && t[i].IsSymbol('('))) break;
            end = Close(t, d, i);
            names.Add(name);
            i = end + 1;
            if (!(i < t.Count && t[i].IsSymbol(','))) break;
            i++;
        }
        return (end < t.Count ? end : -1, names);
    }

    // A name as Postgres reads it: "Quoted" as written, unquoted folded to lower case
    static string Unquote(Token token) => token.Kind == Kind.Quoted
        ? token.Text[1..^1].Replace("\"\"", "\"")
        : token.Text.ToLowerInvariant();

    // The index of the ')' closing the '(' at i, or past the last token when none does
    static int Close(List<Token> t, int[] d, int i)
    {
        for (int k = i + 1; k < t.Count; k++)
            if (t[k].IsSymbol(')') && d[k] == d[i]) return k;
        return t.Count;
    }

    // Each token's depth in parentheses, a '(' and its ')' at the depth around them
    static int[] Depths(List<Token> t)
    {
        var depths = new int[t.Count];
        int depth = 0;
        for (int i = 0; i < t.Count; i++)
        {
            if (t[i].IsSymbol(')')) depth = Math.Max(depth - 1, 0);
            depths[i] = depth;
            if (t[i].IsSymbol('(')) depth++;
        }
        return depths;
    }

    // The tokens of the statement around the cursor, its ';' left out: the last one starting
    // at or before it. Null when there is none
    static List<Token>? StatementAt(string text, int cursor)
    {
        List<Token>? found = null;
        foreach (var statement in Statements(Tokens(text)))
        {
            if (statement[0].Start > cursor) break;
            found = statement;
        }
        return found;
    }

    // The statements, cut where psql cuts them: at a ';' outside parentheses and outside the
    // BEGIN ... END of a BEGIN ATOMIC body, which psql tracks by counting BEGIN and CASE after
    // a statement's first word against END
    static List<List<Token>> Statements(List<Token> tokens)
    {
        var statements = new List<List<Token>>();
        var current = new List<Token>();
        int parens = 0, begins = 0;
        foreach (var token in tokens)
        {
            if (token.IsSymbol(';') && parens == 0 && begins == 0)
            {
                if (current.Count > 0) statements.Add(current);
                current = new List<Token>();
                continue;
            }
            if (token.IsSymbol('(')) parens++;
            else if (token.IsSymbol(')')) parens = Math.Max(parens - 1, 0);
            else if ((token.Is("begin") || token.Is("case")) && current.Count > 0) begins++;
            else if (token.Is("end") && begins > 0) begins--;
            current.Add(token);
        }
        if (current.Count > 0) statements.Add(current);
        return statements;
    }

    // The tokens of the text, without whitespace and comments
    public static List<Token> Tokens(string text)
    {
        var tokens = new List<Token>();
        int i = 0, n = text.Length;
        while (i < n)
        {
            char c = text[i];
            if (char.IsWhiteSpace(c)) { i++; continue; }
            if (c == '-' && i + 1 < n && text[i + 1] == '-')
            {
                int line = text.IndexOf('\n', i);
                i = line < 0 ? n : line + 1;
                continue;
            }
            if (c == '/' && i + 1 < n && text[i + 1] == '*')
            {
                // Nested, unlike SQL Server's
                int depth = 0;
                do
                {
                    int open = text.IndexOf("/*", i, StringComparison.Ordinal), close = text.IndexOf("*/", i, StringComparison.Ordinal);
                    if (close < 0) { i = n; break; }
                    if (open >= 0 && open < close) { depth++; i = open + 2; }
                    else { depth--; i = close + 2; }
                } while (depth > 0);
                continue;
            }

            int start = i;
            Kind kind;
            if (c == '\'' || c == '"')
            {
                // 'it''s', "a ""name""", and E'it\'s' (its E the word just before)
                bool escapes = false;
                if (c == '\'' && tokens.Count > 0 && tokens[^1] is { Kind: Kind.Word } prefix && prefix.End == i && prefix.Is("e"))
                {
                    escapes = true;
                    start = prefix.Start;
                    tokens.RemoveAt(tokens.Count - 1);
                }
                i++;
                while (i < n)
                {
                    if (escapes && text[i] == '\\') { i += 2; continue; }
                    if (text[i] == c)
                    {
                        if (i + 1 < n && text[i + 1] == c) { i += 2; continue; }
                        break;
                    }
                    i++;
                }
                i = Math.Min(i + 1, n);
                kind = c == '"' ? Kind.Quoted : Kind.String;
            }
            else if (c == '$' && DollarTag(text, i) is { } tag)
            {
                // $$ ... $$ and $tag$ ... $tag$
                int close = text.IndexOf(tag, i + tag.Length, StringComparison.Ordinal);
                i = close < 0 ? n : close + tag.Length;
                kind = Kind.Dollar;
            }
            else if (c == '$' && i + 1 < n && char.IsAsciiDigit(text[i + 1]))
            {
                i++;
                while (i < n && char.IsAsciiDigit(text[i])) i++;
                kind = Kind.Param;
            }
            else if (IsIdentifierStart(c))
            {
                i++;
                while (i < n && (IsIdentifierStart(text[i]) || char.IsAsciiDigit(text[i]) || text[i] == '$')) i++;
                kind = Kind.Word;
            }
            else if (char.IsAsciiDigit(c))
            {
                while (i < n && (char.IsAsciiLetterOrDigit(text[i]) || text[i] == '.' || text[i] == '_')) i++;
                kind = Kind.Number;
            }
            else
            {
                i++;
                kind = Kind.Symbol;
            }
            tokens.Add(new Token(kind, start, i, text[start..i]));
        }
        return tokens;
    }

    static bool IsIdentifierStart(char c) => char.IsLetter(c) || c == '_' || c >= '\u0080';

    // The $tag$ (or $$) opening a dollar-quoted string at i, null when there is none ($1 is a parameter)
    static string? DollarTag(string text, int i)
    {
        int k = i + 1;
        if (k < text.Length && text[k] == '$') return "$$";
        if (k >= text.Length || !IsIdentifierStart(text[k])) return null;
        while (k < text.Length && (IsIdentifierStart(text[k]) || char.IsAsciiDigit(text[k]))) k++;
        return k < text.Length && text[k] == '$' ? text[i..(k + 1)] : null;
    }
}
