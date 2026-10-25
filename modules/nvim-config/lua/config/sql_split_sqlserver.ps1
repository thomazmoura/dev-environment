# Where the T-SQL statements around the cursor start and end, for <Leader>r in sql buffers
# (config/sql_statement.lua), what a SELECT * reads from, for gd on it (config/sql_star.lua),
# and the tables of the join whose ON is being written, for its completion
# (config/sql_join.lua), all through config/sql_split_sqlserver.lua. It parses with
# ScriptDom, the parser of SSMS and VS Code's mssql, from SqlToolsService's install.
#
# It stays running, one request per line on stdin and one answer per line on stdout, or
# {"error": "..."}:
#   {"text": "...", "cursor": n}  →  {"statements": [[start, end], ...]}
#     The statements of the cursor's GO batch, up to the first one ending past the cursor.
#     A statement that doesn't parse is still one: what lies between the ones around it.
#   {"kind": "star", "text": "...", "cursor": n}  →  {"star": [start, end], "qualifier": "o",
#     "sources": ["c", "o"], "aliased": [true, true], "with": "WITH ...", "from": "FROM ..."}
#     The * (or o.*) under the cursor, the names its FROM's tables and views go by there
#     (alias, else name), whether that name is an alias, and the text of its FROM and of its
#     statement's CTEs. qualifier and with are absent when it has none. star is
#     {"star": null} off a select list's *.
#   {"kind": "join", "text": "...", "cursor": n}  →  {"join": {"joined": [{"schema": "dbo",
#     "table": "Customers", "name": "c"}], "earlier": [{"schema": null, "table": "Orders",
#     "name": "o"}]}}
#     The tables of the join whose ON has no condition yet at the cursor: the one it joins
#     (several for a parenthesized join) and the ones before it, nearest last. schema and table
#     are the names unquoted, schema null when not written, and name what the table goes by
#     there (alias, else name). Views, subqueries, CTEs and other databases' tables are left
#     out. join is {"join": null} off such an ON.
#   {"kind": "quote", "names": ["Id", "Total Value", "Order"]}  →  {"names": ["Id",
#     "[Total Value]", "[Order]"]}: column names bracketed where T-SQL needs it.
# Offsets are UTF-8 bytes, as NeoVim counts them, with the end excluded.
param(
  [string]$ScriptDomDll = "$HOME/.language-servers/sqlserver/Microsoft.SqlServer.TransactSql.ScriptDom.dll"
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

Add-Type -Path $ScriptDomDll

# C#, as a PowerShell loop over the tokens of a long file takes seconds. Compiled once per
# version of it into the cache (compiling takes 3s), loaded from there afterwards
$source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using Microsoft.SqlServer.TransactSql.ScriptDom;

public static class SqlServerSplitter
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
        return (TSqlParser)Activator.CreateInstance(versions.Last().Type, new object[] { true });
    }

    public static void Serve()
    {
        string line;
        while ((line = Console.In.ReadLine()) != null)
        {
            string answer;
            try
            {
                using var request = JsonDocument.Parse(line);
                var root = request.RootElement;
                var kind = root.TryGetProperty("kind", out var k) ? k.GetString() : "split";
                answer = kind switch
                {
                    "star" => Star(root.GetProperty("text").GetString(), root.GetProperty("cursor").GetInt32()),
                    "join" => Join(root.GetProperty("text").GetString(), root.GetProperty("cursor").GetInt32()),
                    "quote" => Quote(root.GetProperty("names").EnumerateArray().Select(n => n.GetString())),
                    _ => Answer(root.GetProperty("text").GetString(), root.GetProperty("cursor").GetInt32()),
                };
            }
            catch (Exception e)
            {
                answer = "{\"error\":" + JsonSerializer.Serialize(e.Message) + "}";
            }
            Console.Out.WriteLine(answer);
            Console.Out.Flush();
        }
    }

    static string Answer(string text, int cursorByte)
    {
        int cursor = ToChar(text, cursorByte);
        var pairs = Statements(text, cursor).Select(s => "[" + ToByte(text, s.Start) + "," + ToByte(text, s.End) + "]");
        return "{\"statements\":[" + string.Join(",", pairs) + "]}";
    }

    static int ToChar(string text, int offsetByte)
    {
        var bytes = Encoding.UTF8.GetBytes(text);
        return Encoding.UTF8.GetCharCount(bytes, 0, Math.Clamp(offsetByte, 0, bytes.Length));
    }

    static int ToByte(string text, int offset) => Encoding.UTF8.GetByteCount(text.AsSpan(0, offset));

    // The select list's * holding the cursor, in the statement holding it
    static string Star(string text, int cursorByte)
    {
        int cursor = ToChar(text, cursorByte);
        var around = Statements(text, cursor).FirstOrDefault(s => s.Start <= cursor && cursor < s.End);
        if (around.End == 0) return "{\"star\":null}";
        var statementText = text.Substring(around.Start, around.End - around.Start);
        var script = Parser.Parse(new StringReader(statementText), out var errors) as TSqlScript;
        var statement = script?.Batches.SelectMany(b => b.Statements).FirstOrDefault();
        if (statement == null || errors.Count > 0) return "{\"star\":null}";

        string Text(TSqlFragment f) => statementText.Substring(f.StartOffset, f.FragmentLength);
        var specs = new QuerySpecifications();
        statement.Accept(specs);
        int local = cursor - around.Start;
        foreach (var spec in specs.Found)
        {
            var star = spec.SelectElements.OfType<SelectStarExpression>()
                .FirstOrDefault(e => e.StartOffset <= local && local < e.StartOffset + e.FragmentLength);
            if (star == null) continue;
            if (spec.FromClause == null) throw new Exception("the * reads from no FROM");

            var sources = spec.FromClause.TableReferences.SelectMany(Flatten).Select(r =>
                r is TableReferenceWithAlias { Alias: not null } aliased ? (Name: Text(aliased.Alias), Aliased: true)
                : r is NamedTableReference named ? (Name: Text(named.SchemaObject.BaseIdentifier), Aliased: false)
                : throw new Exception("a table of the FROM has no name to read its columns by: " + Text(r))).ToList();
            var with = (statement as StatementWithCtesAndXmlNamespaces)?.WithCtesAndXmlNamespaces;
            var answer = new Dictionary<string, object>
            {
                ["star"] = new[] { ToByte(text, around.Start + star.StartOffset), ToByte(text, around.Start + star.StartOffset + star.FragmentLength) },
                ["sources"] = sources.Select(s => s.Name).ToList(),
                ["aliased"] = sources.Select(s => s.Aliased).ToList(),
                ["from"] = Text(spec.FromClause),
            };
            if (star.Qualifier != null) answer["qualifier"] = Text(star.Qualifier);
            if (with != null) answer["with"] = Text(with);
            return JsonSerializer.Serialize(answer);
        }
        return "{\"star\":null}";
    }

    // The tables of the join whose ON is at the cursor, with no condition yet. Such a
    // statement doesn't parse, so it is parsed with a placeholder condition at the cursor
    static string Join(string text, int cursorByte)
    {
        int cursor = ToChar(text, cursorByte);
        text = text.Insert(cursor, " 1=1 ");
        cursor++;
        var around = Statements(text, cursor).FirstOrDefault(s => s.Start <= cursor && cursor < s.End);
        if (around.End == 0) return "{\"join\":null}";
        var statementText = text.Substring(around.Start, around.End - around.Start);
        var script = Parser.Parse(new StringReader(statementText), out var errors) as TSqlScript;
        var statement = script?.Batches.SelectMany(b => b.Statements).FirstOrDefault();
        if (statement == null || errors.Count > 0) return "{\"join\":null}";

        var joins = new QualifiedJoins();
        statement.Accept(joins);
        int local = cursor - around.Start;
        var join = joins.Found.FirstOrDefault(j => j.SearchCondition.StartOffset == local);
        if (join == null) return "{\"join\":null}";

        string Text(TSqlFragment f) => statementText.Substring(f.StartOffset, f.FragmentLength);
        var ctes = ((statement as StatementWithCtesAndXmlNamespaces)?.WithCtesAndXmlNamespaces?.CommonTableExpressions
            .Select(c => c.ExpressionName.Value) ?? Enumerable.Empty<string>()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        List<object> Tables(TableReference side) => Flatten(side).OfType<NamedTableReference>()
            .Where(t => t.SchemaObject.DatabaseIdentifier == null && t.SchemaObject.ServerIdentifier == null
                && !(t.SchemaObject.SchemaIdentifier == null && ctes.Contains(t.SchemaObject.BaseIdentifier.Value)))
            .Select(t => (object)new Dictionary<string, string>
            {
                ["schema"] = t.SchemaObject.SchemaIdentifier?.Value,
                ["table"] = t.SchemaObject.BaseIdentifier.Value,
                ["name"] = Text(t.Alias ?? (TSqlFragment)t.SchemaObject.BaseIdentifier),
            }).ToList();
        return JsonSerializer.Serialize(new { join = new { joined = Tables(join.SecondTableReference), earlier = Tables(join.FirstTableReference) } });
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

    // A name stays bare when ScriptDom reads it back as one identifier: not a keyword, no spaces...
    static string Quote(IEnumerable<string> names)
    {
        var quoted = names.Select(name =>
        {
            var tokens = Parser.GetTokenStream(new StringReader(name), out var errors)
                .Where(t => t.TokenType != TSqlTokenType.EndOfFile).ToList();
            bool bare = errors.Count == 0 && tokens.Count == 1 && tokens[0].TokenType == TSqlTokenType.Identifier
                && tokens[0].Text == name;
            return bare ? name : "[" + name.Replace("]", "]]") + "]";
        });
        return JsonSerializer.Serialize(new { names = quoted });
    }

    static List<(int Start, int End)> Statements(string text, int cursor)
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
'@

$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($source))).Substring(0, 16)
$cache = Join-Path ($env:XDG_CACHE_HOME ?? "$HOME/.cache") 'nvim/sql_split_sqlserver'
$assembly = Join-Path $cache "$hash.dll"
if (-not [IO.File]::Exists($assembly)) {
  [void][IO.Directory]::CreateDirectory($cache)
  $references = @(
    $ScriptDomDll, 'netstandard', 'System.Runtime', 'System.Collections', 'System.Linq', 'System.Console',
    'System.Memory', 'System.Text.Json', 'System.Text.RegularExpressions'
  )
  # CS1701: ScriptDom is built for .NET 8, pwsh runs a newer one
  $partial = "$assembly.$PID"
  Add-Type -IgnoreWarnings -WarningAction SilentlyContinue -ReferencedAssemblies $references `
    -TypeDefinition $source -OutputAssembly $partial -OutputType Library
  [IO.File]::Move($partial, $assembly, $true)
  Get-ChildItem $cache -Filter *.dll | Where-Object FullName -ne $assembly | Remove-Item -ErrorAction Ignore
}
Add-Type -Path $assembly

[SqlServerSplitter]::Serve()
