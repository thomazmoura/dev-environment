# Where the T-SQL statements around the cursor start and end, for <Leader>r in sql buffers
# (config/sql_statement.lua through config/sql_split_sqlserver.lua). It parses with
# ScriptDom, the parser of SSMS and VS Code's mssql, from SqlToolsService's install.
#
# It stays running, one request per line on stdin, {"text": "...", "cursor": n}, and one
# answer per line on stdout: {"statements": [[start, end], ...]}, or {"error": "..."}.
# Offsets are UTF-8 bytes, as NeoVim counts them, with the end excluded. The statements are
# those of the cursor's GO batch, up to the first one ending past the cursor. A statement
# that doesn't parse is still one: what lies between the ones around it.
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
                answer = Answer(request.RootElement.GetProperty("text").GetString(),
                    request.RootElement.GetProperty("cursor").GetInt32());
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
        var bytes = Encoding.UTF8.GetBytes(text);
        int cursor = Encoding.UTF8.GetCharCount(bytes, 0, Math.Clamp(cursorByte, 0, bytes.Length));

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

        var pairs = Split(text, tokens, start, end, cursor).Select(s => "["
            + Encoding.UTF8.GetByteCount(text.AsSpan(0, s.Start)) + ","
            + Encoding.UTF8.GetByteCount(text.AsSpan(0, s.End)) + "]");
        return "{\"statements\":[" + string.Join(",", pairs) + "]}";
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
