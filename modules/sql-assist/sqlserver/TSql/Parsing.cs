// What ScriptDom, the parser of SSMS and VS Code's mssql, reads from a T-SQL document: where its
// statements start and end, the select list's * under the cursor, the tables of the join
// whose ON is being written, and how names are quoted. Offsets are string indices (UTF-16),
// the end excluded.
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace SqlServerAssist.TSql;

// The * (or o.*) of a select list: the names its FROM's tables and views go by there (alias,
// else name), whether that name is an alias, and the text of its FROM and of its statement's
// CTEs. Qualifier and With are null when it has none
public record Star(int Start, int End, string? Qualifier, List<string> Sources, List<bool> Aliased, string? With, string From);

// A table of a join, schema and table unquoted (schema null when not written), and what it
// goes by there (alias, else name)
public record JoinTable(string? Schema, string Table, string Name);

// The tables a join joins (several for a parenthesized join), and the ones before it, nearest last
public record Join(List<JoinTable> Joined, List<JoinTable> Earlier);

public static class Parsing
{
    // A token other than whitespace and comments, and whether a statement can start at it
    struct Token { public int Start, End; public bool Go, Leads; }

    static readonly TSqlParser Parser = Newest();

    // The newest T-SQL the DLL knows (TSql180Parser in ScriptDom 18), with quoted identifiers on
    static TSqlParser Newest()
    {
        var versions = typeof(TSqlParser).Assembly.GetTypes()
            .Select(t => (Type: t, Match: System.Text.RegularExpressions.Regex.Match(t.Name, @"^TSql(\d+)Parser$")))
            .Where(t => t.Match.Success)
            .OrderBy(t => int.Parse(t.Match.Groups[1].Value));
        return (TSqlParser)Activator.CreateInstance(versions.Last().Type, new object[] { true })!;
    }

    // The statement holding the cursor, parsed alone, or null when there is none or it
    // doesn't parse
    static (int Start, string Text, TSqlStatement Statement)? StatementAt(string text, int cursor)
    {
        var around = Statements(text, cursor).FirstOrDefault(s => s.Start <= cursor && cursor < s.End);
        if (around.End == 0) return null;
        var statementText = text.Substring(around.Start, around.End - around.Start);
        var script = Parser.Parse(new StringReader(statementText), out var errors) as TSqlScript;
        var statement = script?.Batches.SelectMany(b => b.Statements).FirstOrDefault();
        if (statement == null || errors.Count > 0) return null;
        return (around.Start, statementText, statement);
    }

    // The select list's * holding the cursor, null off one. Throws when it is one but can't be
    // expanded, with why
    public static Star? StarAt(string text, int cursor)
    {
        if (StatementAt(text, cursor) is not { } found) return null;
        var (start, statementText, statement) = found;

        string Text(TSqlFragment f) => statementText.Substring(f.StartOffset, f.FragmentLength);
        var specs = new QuerySpecifications();
        statement.Accept(specs);
        int local = cursor - start;
        foreach (var spec in specs.Found)
        {
            var star = spec.SelectElements.OfType<SelectStarExpression>()
                .FirstOrDefault(e => e.StartOffset <= local && local < e.StartOffset + e.FragmentLength);
            if (star == null) continue;
            if (spec.FromClause == null) throw new InvalidOperationException("the * reads from no FROM");

            var sources = spec.FromClause.TableReferences.SelectMany(Flatten).Select(r =>
                r is TableReferenceWithAlias { Alias: not null } aliased ? (Name: Text(aliased.Alias), Aliased: true)
                : r is NamedTableReference named ? (Name: Text(named.SchemaObject.BaseIdentifier), Aliased: false)
                : throw new InvalidOperationException("a table of the FROM has no name to read its columns by: " + Text(r))).ToList();
            var with = (statement as StatementWithCtesAndXmlNamespaces)?.WithCtesAndXmlNamespaces;
            return new Star(
                start + star.StartOffset, start + star.StartOffset + star.FragmentLength,
                star.Qualifier != null ? Text(star.Qualifier) : null,
                sources.Select(s => s.Name).ToList(), sources.Select(s => s.Aliased).ToList(),
                with != null ? Text(with) : null, Text(spec.FromClause));
        }
        return null;
    }

    // The tables of the join whose ON is at the cursor, with no condition yet, or null. Such a
    // statement doesn't parse, so it is parsed with a placeholder condition at the cursor
    public static Join? JoinAt(string text, int cursor)
    {
        text = text.Insert(cursor, " 1=1 ");
        cursor++;
        if (StatementAt(text, cursor) is not { } found) return null;
        var (start, statementText, statement) = found;

        var joins = new QualifiedJoins();
        statement.Accept(joins);
        int local = cursor - start;
        var join = joins.Found.FirstOrDefault(j => j.SearchCondition.StartOffset == local);
        if (join == null) return null;

        string Text(TSqlFragment f) => statementText.Substring(f.StartOffset, f.FragmentLength);
        var ctes = ((statement as StatementWithCtesAndXmlNamespaces)?.WithCtesAndXmlNamespaces?.CommonTableExpressions
            .Select(c => c.ExpressionName.Value) ?? Enumerable.Empty<string>()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        List<JoinTable> Tables(TableReference side) => Flatten(side).OfType<NamedTableReference>()
            .Where(t => t.SchemaObject.DatabaseIdentifier == null && t.SchemaObject.ServerIdentifier == null
                && !(t.SchemaObject.SchemaIdentifier == null && ctes.Contains(t.SchemaObject.BaseIdentifier.Value)))
            .Select(t => new JoinTable(t.SchemaObject.SchemaIdentifier?.Value, t.SchemaObject.BaseIdentifier.Value,
                Text(t.Alias ?? (TSqlFragment)t.SchemaObject.BaseIdentifier)))
            .ToList();
        return new Join(Tables(join.SecondTableReference), Tables(join.FirstTableReference));
    }

    class QualifiedJoins : TSqlFragmentVisitor
    {
        public readonly List<QualifiedJoin> Found = new();
        public override void Visit(QualifiedJoin node) => Found.Add(node);
    }

    // The tables, views, subqueries... of a FROM, in order, out of its joins
    static IEnumerable<TableReference> Flatten(TableReference reference) => reference switch
    {
        JoinTableReference join => Flatten(join.FirstTableReference).Concat(Flatten(join.SecondTableReference)),
        JoinParenthesisTableReference parenthesis => Flatten(parenthesis.Join),
        _ => new[] { reference },
    };

    class QuerySpecifications : TSqlFragmentVisitor
    {
        public readonly List<QuerySpecification> Found = new();
        public override void Visit(QuerySpecification node) => Found.Add(node);
    }

    // Column names bracketed where T-SQL needs it. A name stays bare when ScriptDom reads it
    // back as one identifier: not a keyword, no spaces...
    public static List<string> Quote(IEnumerable<string> names) => names.Select(name =>
    {
        var tokens = Parser.GetTokenStream(new StringReader(name), out var errors)
            .Where(t => t.TokenType != TSqlTokenType.EndOfFile).ToList();
        bool bare = errors.Count == 0 && tokens.Count == 1 && tokens[0].TokenType == TSqlTokenType.Identifier
            && tokens[0].Text == name;
        return bare ? name : "[" + name.Replace("]", "]]") + "]";
    }).ToList();

    // The statements of the cursor's GO batch, up to the first one ending past the cursor. A
    // statement that doesn't parse is still one: what lies between the ones around it
    public static List<(int Start, int End)> Statements(string text, int cursor)
    {
        // What a statement that doesn't parse is cut from, and the GO lines between batches.
        // A statement can start at a token that starts a line or follows a ';'
        var tokens = new List<Token>();
        int previousLine = 0;
        bool afterSemicolon = false;
        foreach (var t in Parser.GetTokenStream(new StringReader(text), out _))
        {
            if (t.TokenType == TSqlTokenType.WhiteSpace || t.TokenType == TSqlTokenType.SingleLineComment
                || t.TokenType == TSqlTokenType.MultilineComment || t.TokenType == TSqlTokenType.EndOfFile) continue;
            tokens.Add(new Token
            {
                Start = t.Offset, End = t.Offset + t.Text.Length, Go = t.TokenType == TSqlTokenType.Go,
                Leads = t.Line != previousLine || afterSemicolon,
            });
            previousLine = t.Line;
            afterSemicolon = t.TokenType == TSqlTokenType.Semicolon;
        }

        // The cursor's batch: from the previous GO to its own (its GO line included, so
        // the cursor there gets the batch's last statement)
        int start = 0, end = text.Length;
        foreach (var t in tokens.Where(t => t.Go))
        {
            if (t.End <= cursor) start = t.End;
            else { end = t.Start; break; }
        }

        return Split(text, tokens, start, end, cursor);
    }

    static List<(int Start, int End)> Split(string text, List<Token> tokens, int start, int end, int cursor)
    {
        var found = new List<(int, int)>();
        int brokenFrom = -1;

        // The statement that doesn't parse: its tokens from brokenFrom up to upTo
        void CloseBroken(int upTo)
        {
            if (brokenFrom < 0) return;
            var inside = tokens.Where(t => t.Start >= brokenFrom && t.End <= upTo && !t.Go).ToList();
            if (inside.Count > 0) found.Add((inside[0].Start, inside[^1].End));
            brokenFrom = -1;
        }

        int pos = start;
        while (true)
        {
            var script = Parser.Parse(new StringReader(text.Substring(pos, end - pos)), out var errors) as TSqlScript;
            int errorAt = errors.Count > 0 ? pos + errors.Min(e => e.Offset) : int.MaxValue;

            // ScriptDom keeps the statements before the first error
            int lastEnd = pos;
            foreach (var statement in script?.Batches.SelectMany(b => b.Statements) ?? Enumerable.Empty<TSqlStatement>())
            {
                int s = pos + statement.StartOffset, e = s + statement.FragmentLength;
                if (e > errorAt) break;
                CloseBroken(s);
                found.Add((s, e));
                lastEnd = e;
                if (e > cursor) return found;
            }
            if (errors.Count == 0) break;

            // The statement in error starts after the last good one. The parse starts again
            // at the first token a statement can start at from the one it failed on, which
            // is often the next statement, and past where it started. Each parse runs to the
            // end of the batch, so a long one with many broken statements takes a while
            if (brokenFrom < 0) brokenFrom = lastEnd;
            int from = Math.Max(errorAt, pos + 1);
            var restart = tokens.FirstOrDefault(t => t.Start >= from && t.Start < end && t.Leads);
            if (restart.End == 0) break;
            pos = restart.Start;
        }
        CloseBroken(end);
        return found;
    }
}
