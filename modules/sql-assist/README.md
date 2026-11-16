# sql-assist

Language servers for the SQL features the dialects' own servers lack, as SQL Prompt adds them
to SSMS. Each one runs next to its dialect's server, not instead of it:

| Folder | Server | Runs next to | Client today |
|---|---|---|---|
| `sqlserver/` | `sqlserver-assist` (C#, ScriptDom + SqlClient) | SqlToolsService (`sqlserver_ls`) | NeoVim (`sqlserver_assist`) |
| `postgres/` | `postgres-assist` (C#, its own tokenizer + Npgsql) | postgres-language-server (`postgres_lsp`) | NeoVim (`postgres_assist`) |

`common/` holds what both share, compiled into each (`<Compile Include="../common/**/*.cs">`):
the LSP plumbing (`Host.cs`, `Server.cs`, `Lsp.cs`, `Documents.cs`), `Hardening.cs`, the
connections' cache (`Connections.cs`), and the features' logic (`Features/`), which each
dialect fills with its parser, its catalog's queries and its quoting. A VS Code extension would
go in `vscode/` (see below).

## What sqlserver-assist does

- **Code actions** (`<Leader>.` in NeoVim):
  - **Expand \*** on a select list's `*` (or `o.*`): its columns, each with the table's alias,
    from `sys.dm_exec_describe_first_result_set`, so views, CTEs, subqueries and APPLY expand
    as the server sees them.
  - **Toggle ;** on a statement (`<Leader>;`): ends it with a `;`, or takes its `;` away.
    **Toggle ; in all statements** (`<Leader>:`) adds one to each statement missing it, else
    takes them all away. The statements are `sqlserver/statements`' ones. A `;` T-SQL requires
    stays: a `MERGE`'s, and the one before a `WITH` or a `THROW`.
- **Completion:**
  - after a join's `ON`: the conditions of the foreign keys between the joined table and the
    ones before it (`o.CustomerId = c.Id`), nearest tables first;
  - after `INSERT [INTO] <table> (`: all the columns an INSERT can set, as one item.
- **`sqlserver/statements`:** where the statements around the cursor start and end. T-SQL
  needs no `;` between statements, so only a parser can tell. NeoVim's `<Leader>r` runs the
  one under the cursor.

## What postgres-assist does

The same, for Postgres:

- **Expand \*** (`<Leader>.`): the columns from the server's own description of the probe
  (Npgsql's `SchemaOnly`: parsed and planned, never run, in a read-only transaction), so
  views, subqueries, CTEs and `LATERAL` functions expand as Postgres sees them. Names are
  quoted as `quote_ident()` would, from the server's `pg_get_keywords()`.
- **Completion:** after a join's `ON`, the foreign keys' conditions (`pg_constraint`; a table
  without its schema is found along the search path), and after `INSERT [INTO] <table> (`,
  the columns an INSERT sets (`pg_attribute`, without identity, generated and serial columns).

No "Toggle ;" (Postgres requires every `;`) and no statements request: `<Leader>r` cuts Postgres
statements in Lua (`config/sql_split_postgres.lua`). Postgres has no parser to call from C#
(libpg_query is native), so `postgres/Pg/Parsing.cs` reads tokens with psql's rules for
strings, quoted names, comments and `$$` bodies, and a SELECT's clauses by their keywords at its
parentheses' depth: enough to find the `*`, its FROM and a join's tables. The server checks the
probe built from them.

## Building

```powershell
pwsh -File ~/.modules/sql-assist/Build-SqlAssist.ps1
```

This publishes to `~/.language-servers/sqlserver-assist/SqlServerAssist` and
`~/.language-servers/postgres-assist/PostgresAssist` (framework-dependent, `net8.0`, rolling
forward to newer runtimes). Intermediate files go to `~/.cache/sql-assist`,
so the repo never gets `bin/` or `obj/`. `modules/neovim-lsp/Setup-NeoVimLSP.ps1` runs it on
setup and in the Docker image. After changing the C#, run it again and `:lsp restart` in NeoVim.

## Adding a feature

Code actions live in each dialect's `CodeActions/` and completions in its `Completions/`. To add one:

1. Write a class implementing `ICodeAction` or `ICompletion` (`common/Features.cs`). One both
   dialects have goes in `common/Features/` as a base class, each dialect's class filling in
   its parser and queries.
2. Add it to the dialect's `CodeActions.All` or `Completions.All`.

The server builds its capabilities (code action kinds, trigger characters) from those lists.

- A code action's `Offers` runs on every code action menu, so it may only parse.
  `Resolve` runs once the action is picked: queries go there.
- A completion's `Complete` runs on every completion request. It returns nothing, and quickly,
  where it doesn't apply.
- Database access goes through `SqlServerConnections.Query` (SqlClient) or
  `PostgresConnections.Query` (Npgsql, `$1` parameters) on `context.ConnectionString`. Use
  `context.Connections.Cached` for anything read once per connection.
- Throw `FeatureException` with a message for the user. It is shown prefixed by the
  feature's name.

## Protocol

Standard LSP over stdio, with positions in UTF-16 (LSP's default):

| Method | Direction | |
|---|---|---|
| `initialize` | → | Capabilities: full text sync, `codeActionProvider` with `resolveProvider`, `completionProvider` with the trigger characters |
| `textDocument/didOpen`, `didChange`, `didClose` | → | The whole text each time |
| `textDocument/codeAction` | → | The actions offered at the range's start. No edit, just `data: { id, uri, version, position }` |
| `codeAction/resolve` | → | Does the work and returns `edit.documentChanges`, versioned so a stale edit is refused. Failures come back as an LSP error with a message |
| `textDocument/completion` | → | Items with a `textEdit` over the word typed |
| `window/showMessage` | ← | A completion's failure (unreachable server...) |
| `sqlserver/connection` | → | sqlserver-assist. Notification `{ textDocument: { uri }, connectionString: string \| null }`: the document's SqlClient connection string, or none |
| `postgres/connection` | → | postgres-assist. The same, with an Npgsql connection string |
| `sqlserver/statements` | → | sqlserver-assist. Request `{ textDocument, position }` → `Range[]`: the statements of the position's GO batch, up to the first one ending past it. A statement that doesn't parse is still one: what lies between the ones around it |

Without a connection, the parse-only parts still work (`sqlserver/statements`, "Toggle ;",
offering "Expand *"). The ones that need the database do nothing, or say why.

## Secrets

The connection string holds the password. Both servers are built so it doesn't leak:

- **It travels over the server's stdin only.** Never argv or environment variables (unlike
  `env SQLCMDPASSWORD=… sqlcmd`, whose argv every user can read in `/proc`).
- **On Linux, other processes can't read it** (`common/Hardening.cs`), even when they run as the
  same user:
  - The process makes itself non-dumpable before it reads anything, so `/proc/<pid>/fd`, `mem`
    and `environ`, ptrace and core dumps are refused.
  - It runs without the .NET diagnostics server. Clients should launch it with
    `DOTNET_EnableDiagnostics=0`; otherwise it re-executes itself with that set.
- **It is never logged.** It stays in memory only, per document, until `didClose`.
  `Persist Security Info` is forced off.
- **Clients must not log it either.** NeoVim's `sql_connection.lua` sends nothing while the LSP
  log level is DEBUG, where `lsp.log` would record it.

## A VS Code client

The servers need nothing VS Code-specific. An extension would need, for sqlserver-assist:

- `vscode-languageclient`, launching the published binary for `sql` documents, with
  `DOTNET_EnableDiagnostics=0` in its environment;
- a `sqlserver/connection` notification per document, with the connection string the mssql
  extension's API gives for that document's connection, and `null` when it disconnects;
- a command for `sqlserver/statements`, if running the statement under the cursor is wanted.
  mssql already has its own.
