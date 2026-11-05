# .NET debugging in NeoVim

VS Code-style debugging for .NET on top of nvim-dap and
[netcoredbg](https://github.com/Samsung/netcoredbg) (installed by
`modules/debugging/Install-NetCoreDbg.ps1`). The keys live in
`lua/plugins/debug.lua`; everything else is in this folder.

| Key | What it does |
|---|---|
| `<Leader>dr` | Debug the project of the current buffer. When a session is already running it continues instead, like F5. If the project is running under `dotnet watch`, it attaches to it |
| `<Leader>dR` | Debug a project picked (fuzzily, through telescope-ui-select) from the runnable ones under the cwd |
| `<Leader>dt` | Debug the test method under the cursor, or every test in the class under it |
| `<Leader>d.` | Repeat the last of those three (it rebuilds) |
| `<Leader>ds` | Stop. A process you attached to (the watched app, a test host) is detached from and keeps running |

Stepping and breakpoints keep their keys: `dh` continue, `dj`/`dl`/`dk` over/into/out,
`dd`/`dD` breakpoint, `do` REPL.

While a session is running, every `<Leader>d{key}` is also `<M-{key}>` (`<M-j>` steps over,
`<M-k>` out, `<M-h>` continues...). They take those keys over from Harpoon's slots and give them
back when the last session ends (`config/dap_session_keys.lua`).

`gH`, also only during a session, opens the value under the cursor in a centered popup as an
expandable tree (`<CR>` expands, `e` edits, `q` closes), like VS Code's debug hover. `<CR>` does the same in file buffers. Quickfix, terminals and
plugin buffers keep their own `<CR>`.

Typing in dap-ui's Watches pane or the dap REPL completes like a new line after the statement
the debugger stopped at: the locals in scope there, then a variable's members after a `.`.

## How it works

| File | |
|---|---|
| `init.lua` | The API the keys call, and the dap launch/attach |
| `project.lua` | The csproj, msbuild properties, the build, `launchSettings.json` |
| `watch.lua` | Finding the app `dotnet watch` runs |
| `test.lua` | Tree-sitter range, Roslyn's `textDocument/runTests`, the debugger attach handshake |
| `display.lua` | Formatting values by type (Guid, DateTime...) with an expression evaluated in the debuggee |
| `completion.lua` | Roslyn's completion in the Watches pane and the REPL, at the line the debugger stopped at |

### Projects (`<Leader>dr`, `<Leader>dR`)

1. **Which project.** For `dr`, it's the nearest `*.csproj` above the buffer's file, so any file
   in the project works. For `dR`, it's every csproj under the cwd (`fd`, which honours
   `.gitignore`) that looks runnable from its text: `<OutputType>Exe`/`WinExe` or the Web/Worker
   SDK. Test projects are left out, and so are `-windows`-only projects on Linux. An `OutputType`
   that only `Directory.Build.props` sets is missed. Use `dr` from one of its files.
2. **Where the DLL is.** `dotnet msbuild -getProperty:TargetPath …` reports msbuild's own
   answer, RID folders and custom output paths included. A multi-targeted project asks which
   framework to use. A library or test project falls back to the `dR` picker.
3. **dotnet watch.** If the app is already running under `dotnet watch` (see below), it attaches
   to that process with no build.
4. **Build.** Modified C# buffers are saved, then `dotnet build` runs. Errors go to the quickfix
   list, opened in Trouble, and the session doesn't start.
5. **Launch.** The process starts with the project directory as cwd, as `dotnet run` does. It
   uses the first `"commandName": "Project"` profile of `Properties/launchSettings.json`:
   `environmentVariables`, `applicationUrl` (as `ASPNETCORE_URLS`) and `commandLineArgs`.
   Without the profile, a web project would start in Production on port 5000.

**An app that crashes on startup.** netcoredbg breaks on an unhandled exception where it's
rethrown. From an async `Main` that's `ExceptionDispatchInfo.Throw()` under the generated
`<Main>()`, and no frame has a source, so dap only says "Source missing, cannot jump to frame".
`on_stopped` (a listener in `lua/plugins/debug.lua`) then shows the exception's message and
puts the frames of our code from its stack traces (inner exceptions first) in the quickfix
list.

### Tests (`<Leader>dt`)

Roslyn already does this. The `textDocument/runTests` request behind VS Code's "Debug Test"
takes a **range**. Roslyn builds the project, finds the tests inside the range, and runs them
with vstest. All this module chooses is the range, using Tree-sitter:

- Inside a method with `[Fact]`, `[Theory]`, `[Test]`, `[TestCase]`, `[TestCaseSource]`,
  `[TestMethod]` or `[DataTestMethod]`, the range is that method. Every `[InlineData]` case runs.
- Anywhere else in a class (its name, a helper, a field), the range is the innermost class or
  record, so all of its tests run.

The range flashes briefly to show what was picked. With `attachDebugger = true`, Roslyn starts
the test host and sends `workspace/attachDebugger { processId }`. `test.lua` attaches nvim-dap
to that process and answers `{ didAttach = true }` only after dap's `configurationDone`, so the
breakpoints are set before any test runs. NeoVim runs server→client requests in a coroutine,
which lets the handler wait. Progress ("Building project...", "Debugging tests...") updates one
notification. The run's whole output goes to `dotnet-test://output`, which opens when a test
fails or none ran.

The handlers are registered on the roslyn client in `lua/plugins/lsp.lua`.

**Roslyn is started directly, not through roslyn.nvim's shared daemon.** vstest needs
`--extensionLogDirectory`; without it every run fails with "Value cannot be null.
(Parameter 'LogFilePath')". The `roslyn-language-server` thin client forwards only the transport
and `--clientProcessId`, and its shared daemon starts with neither, so `lsp.lua` runs
`Microsoft.CodeAnalysis.LanguageServer` from the same tool install. Each NeoVim gets its own
server. To go back to the daemon, drop the `cmd` override in `lsp.lua`, which also turns
`<Leader>dt` off.

A test run fails with build errors about a `<File>.csproj` (for example
`SpotlightDimmer.Tests/AppStateTests.csproj`) when Roslyn couldn't load the real test project.
Usually NuGet restore failed, and Roslyn then treats the file as a .NET 10 file-based program.
Run `dotnet restore` on the project and `:lsp restart`.

### dotnet watch (`<Leader>dr`)

`watch.lua` scans `/proc` for a process that runs the project's `TargetPath` (the apphost, or
`dotnet <dll>`) and has `DOTNET_WATCH=1` in its environment. watch sets that only in the app it
launches, which rules out watch itself and a plain `dotnet run`. The newest match wins. Only
processes on the same machine or container are visible.

**Hot reload is off while attached** (checked with .NET 10). The runtime refuses the update
("Assembly updates cannot be applied while a debugger is attached"), and watch then sends **no
further changes to that process, even after you detach**. Press Ctrl+R in watch to restart it.
A restart from watch (a rude edit, Ctrl+R) also ends the debug session; press `<Leader>dr` again
to reattach. Breakpoints and stepping work as usual, and `<Leader>ds` leaves the app running.

## Prior art

[easy-dotnet.nvim](https://github.com/GustavEikaas/easy-dotnet.nvim) (MIT, by Gustav Eikaas)
does all of this and much more. It has a Rider-like test runner and neotest support, launch
profile pickers, NuGet, user secrets and EF commands, and CPU/memory widgets for dapui. It works
through its own `EasyDotnet` NuGet tool server and takes over the Roslyn setup. We don't use it:
we keep roslyn.nvim and the solution handling in `lsp.lua`, and avoid a second, separately
updated server. These ideas come from it:

- build errors in the quickfix list (its `build_quickfix`);
- environment variables from `launchSettings.json` (its `debug_profile`);
- falling back to picking the entry project when the buffer's project is a library;
- flashing the test method or class that was picked.

Worth a look if this module ever grows: its test runner tree, a persisted default startup
project, and running the app in a terminal (`console = integratedTerminal`) for apps that read
stdin. Here, program output goes to the DAP REPL.

Other debug adapters that easy-dotnet bundles, if netcoredbg ever falls short:
[dncdbg](https://github.com/viewizard/dncdbg) (a netcoredbg fork with more features) and
[sharpdbg](https://github.com/MattParkerDev/sharpdbg) (a debugger written in C#).

### Value formatters (`display.lua`)

netcoredbg shows a struct like `Guid` or `DateTime` as its type name: `{System.Guid}`. For the
types in `formatters`, the value is replaced by an expression evaluated in the debuggee,
`{value}` standing for the variable (`exemploDeGuid.ToString()`). Only the text changes: the
value still expands into its members. This covers the inline virtual text, dap-ui's Scopes and
Watches panes, `gH`'s popup and the REPL.

The defaults are `ToString()` for `Guid` and `TimeSpan`, and ISO for `DateTime` (`"s"`:
`2021-11-30T20:36:45`), `DateTimeOffset`, `DateOnly` and `TimeOnly`. A nullable one (`T?`) uses
`T`'s. `lua/plugins/debug.lua` overrides DateTime to `dd/MM/yyyy HH:mm:ss`. A formatter is a
string, a function `(expr, item) -> expression or nil`, or `false` to turn a default off:

```lua
require('config.dotnet_debug.display').setup({
  formatters = {
    ['System.DateTime'] = '{value}.ToString("dd/MM/yyyy HH:mm:ss")',
    ['System.TimeSpan'] = false,
    ['MyApp.Money'] = function(expr) return expr .. '.Amount.ToString("N2")' end,
  },
  unquote = true, -- 54b3… rather than "54b3…"
  timeout_ms = 1000, -- past it, the values not evaluated yet keep netcoredbg's text
})
```

It wraps the session's `request` for `variables` and `evaluate` (coreclr sessions only, hooked
through `dap.listeners.on_session`): the response reaches dap or dap-ui after the evaluations,
and the virtual text, which draws on dap's `after.variables` listener before that, is refreshed
then.

- Each formatted value costs one evaluation per stop or expand, so only expressions with no side
  effects belong there.
- A value with no `evaluateName` (a collection's items, "Static members") keeps netcoredbg's text.
- dap-ui's `e` starts from the formatted text: type a C# expression (`new DateTime(...)`).

### Completion in the Watches pane and the REPL (`completion.lua`)

netcoredbg has no DAP `completions` request, so blink's `dap_roslyn` provider (the only one for
the `dapui_watches` and `dap-repl` filetypes, `lua/plugins/completion.lua`) asks Roslyn instead.
For each request:

1. **Where.** The stopped frame's file and line. Tree-sitter finds the statement that line starts,
   up to its block, so a statement over several lines stays whole: the new line goes after it.
   On a brace it goes after the `{` or before the `}`.
2. **The line.** Roslyn alone gets a `didChange` with the typed expression (the prompt line up to
   the cursor) and a `;` on a new line there. The buffer is untouched: no undo step, not
   modified. Neovim's pending changes are flushed first, so both stay in step.
3. **The completion** at the end of the expression. Then a second `didChange` takes the line out.
   One request at a time: a newer one replaces the one waiting, and a request past 3 seconds is
   dropped, with the text restored all the same.
4. **The items** go to blink without their edits (their ranges are in the C# file, and an added
   `using` has no place in an expression), so they replace the word at the cursor. Snippet items
   are left out. Resolving an item (its signature and docs) puts the line back in for the request,
   since Roslyn describes the item from the text it completed in.

- The C# file must be loaded with Roslyn attached (the debugger opens it when it stops). Until
  Roslyn has loaded the solution, the list is empty.
- A semantic token or diagnostic request of Neovim's landing in those few milliseconds would
  see the extra line. Nothing sends one while you type in the pane.
