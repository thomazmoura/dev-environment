# A lean profile for panes that run one command and exit (PWSH_LEAN=1, set by
# pwsh_invocation in modules/tmux/scripts/tmux-helpers.sh): they get the same
# environment, functions, ssh-agent and code-scripts, but skip what only a
# prompt uses -- PSReadLine, completers and oh-my-posh (linux-profile.ps1).
# Cleared right away so a pwsh started from inside the tool (Claude's shell,
# NeoVim's :terminal) gets the full profile again.
$global:LeanProfile = [bool]$env:PWSH_LEAN
$env:PWSH_LEAN = $null

# Startup speed: everything up to the first prompt sticks to Core cmdlets, .NET
# calls and $ExecutionContext. A bare interactive pwsh loads no module but
# PSReadLine, and the first cmdlet from Microsoft.PowerShell.Management
# (Test-Path, Get-ChildItem, Get-Content...) imports it for 130-200ms; the first
# from Microsoft.PowerShell.Utility (Write-Verbose, New-Alias,
# Register-EngineEvent...) another 65-110ms. Both are imported on the first
# idle tick instead (below).
$InformationPreference = "Continue";

# Helper functions and their aliases autoload from here on first use (DevHelpers).
$env:PSModulePath = "$HOME/.modules/powershell/Modules$([IO.Path]::PathSeparator)$env:PSModulePath"

. $HOME/.modules/powershell/pwsh-modules.ps1

if([IO.File]::Exists("$HOME/.profile.ps1")) {
  . $HOME/.profile.ps1
}

if (!$global:LeanProfile) {
  # PSReadLine's setup waits for its first idle tick (300ms without a key, so
  # right after the first prompt): done eagerly it cost ~150ms of every shell
  # start. Keys typed before that pause still get the default bindings.
  # SubscribeEvent is what Register-EngineEvent calls, minus the Utility import.
  $null = $ExecutionContext.Events.SubscribeEvent($null, $null, 'PowerShell.OnIdle', $null, {
    # Vi style cursor: a blinking block in command mode, a blinking line otherwise.
    Set-PSReadLineOption -EditMode Vi -BellStyle None -ViModeIndicator Script -ViModeChangeHandler {
      if ($args[0] -eq 'Command') { Write-Host -NoNewLine "`e[1 q" }
      else { Write-Host -NoNewLine "`e[5 q" }
    }

    # Prediction and a larger history
    try {
      Set-PSReadLineOption -MaximumHistoryCount 20000 -PredictionSource History -Colors @{ InlinePrediction = "#666699" }
    }
    catch {
      Install-Module -Force -AcceptLicense PSReadLine
      Set-PSReadLineOption -PredictionSource History -Colors @{ InlinePrediction = "#666699" }
    }
    Set-PSReadLineKeyHandler -Chord "RightArrow" -Function ForwardWord
    Set-PSReadLineKeyHandler -Chord "End" -Function ForwardChar
    # Ctrl+Space reaches pwsh as a NUL byte, which .NET reads as Ctrl+@ rather
    # than the Ctrl+Spacebar PSReadLine binds, so it typed a literal @. In tmux,
    # where C-Space is the prefix, it is C-Space twice.
    Set-PSReadLineKeyHandler -Chord "Ctrl+@" -Function MenuComplete

    # The native prompt is two lines: PSReadLine has to redraw from the line above.
    Set-PSReadLineOption -ExtraPromptLineCount 1

    # dotnet autocomplete
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
      param($commandName, $wordToComplete, $cursorPosition)
      dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
      }
    }

    # The modules startup avoided, while nobody is typing: the first cd or ls
    # would otherwise pay for them. -Global: an event action runs in a module of
    # its own, which would otherwise be the only one to see them.
    Import-Module -Global Microsoft.PowerShell.Management, Microsoft.PowerShell.Utility
  }, $true, $false, 1)
}

if (! ($env:CODE_FOLDER)) {
  if ( [IO.Directory]::Exists("$HOME/code") ) {
    $env:CODE_FOLDER = "~/code"
  }
  elseif ( [IO.Directory]::Exists("$HOME/git") ) {
    $env:CODE_FOLDER = "~/git"
  }
  elseif ( [IO.Directory]::Exists("/Git") ) {
    $env:CODE_FOLDER = "/Git"
  }
}

# Definição de scripts padrões
# A pwsh started from another one inherits the folders in PATH already. Otherwise
# a plain loop over [IO.Directory]: fd compiled the .gitignore of every repo it
# passed (~150ms), and Get-Item's wildcard plus a pipeline still cost ~100ms.
$cicdFolder = $null
if ($env:CODE_FOLDER -and !$env:PATH.Contains('/CI-CD/Utilitarios')) {
  $codeFolder = $env:CODE_FOLDER.Replace('~', $HOME)
  if ([IO.Directory]::Exists($codeFolder)) {
    foreach ($dir in @($codeFolder) + [IO.Directory]::GetDirectories($codeFolder)) {
      if (!$dir.Contains('code-scripts') -and [IO.Directory]::Exists("$dir/CI-CD")) {
        $cicdFolder = "$dir/CI-CD/"
        break
      }
    }
  }
}
if ($cicdFolder) {
  $env:PATH = "$($cicdFolder)Utilitarios:$($cicdFolder)QuickStarts/Scripts:${env:PATH}"
}
if ( [IO.Directory]::Exists("$HOME/.cargo/bin") -and !($env:PATH.Contains("$HOME/.cargo/bin")) ) {
  $env:PATH = "$HOME/.cargo/bin:${env:PATH}"
}
if ( [IO.Directory]::Exists("$HOME/.local/bin") -and !($env:PATH.Contains("$HOME/.local/bin")) ) {
  $env:PATH = "$HOME/.local/bin:${env:PATH}"
}

function Update-Profile () {
  . $PROFILE.CurrentUserAllHosts
}

function Set-LocalContextDatabase($DatabaseName = "contexto", $ContextName = "Contexto", $DataSourceName = "::1", $UserId = "sa", $Password = "L0c4lD3v!") {
  if (!$DatabaseName) {
    $env:ConnectionStrings__Contexto = $null
  }
  else {
    [Environment]::SetEnvironmentVariable("ConnectionStrings__$ContextName", "Data Source=$DataSourceName;Initial Catalog=$DatabaseName;Persist Security Info=True;User Id=$UserId;Password=$Password;encrypt=false")
  }
}

# Stays in the profile rather than DevHelpers: it is dot-sourced so the scripts'
# functions land in the global scope, and a module function would keep them in
# the module's.
function Run-CodeFolderScripts() {
  $CodeFolder = "$HOME/code/"
  if(!$PWD.Path.StartsWith($CodeFolder)) {
    return
  }

  $CurrentFolder = $PWD.Path.Replace($CodeFolder, "").Replace("AT/", "").Split("/")[0]
  $CodeScriptFolder = "$HOME/code/code-scripts/$CurrentFolder"
  if(![IO.Directory]::Exists($CodeScriptFolder)) {
    return
  }

  $PowerShellScriptsForThisFolder = [IO.Directory]::GetFiles($CodeScriptFolder, "*.ps1")
  [Array]::Sort($PowerShellScriptsForThisFolder)
  foreach($Script in $PowerShellScriptsForThisFolder) {
    . $Script
  }
}

# Aliases through the Alias provider rather than New-Alias, which is a Utility
# cmdlet. It creates them in the current scope, so this has to stay at the top
# level of the profile rather than move into a helper function.
if ( ![IO.File]::Exists("/usr/bin/clip") -and ![IO.File]::Exists("$HOME/.local/bin/clip") ) {
  # A walk over PATH instead of Get-Command, which cost ~10ms per lookup.
  $pathDirs = $env:PATH.Split([IO.Path]::PathSeparator)
  $clip = if ($pathDirs.Where({ [IO.File]::Exists("$_/wl-copy") }, 'First')) { 'wl-copy' }
          elseif ($pathDirs.Where({ [IO.File]::Exists("$_/clip.exe") }, 'First')) { 'clip.exe' }
          else { 'Set-Clipboard' }
  $null = $ExecutionContext.InvokeProvider.Item.New('Alias:\', 'clip', '', $clip, $true)
}

$env:FZF_DEFAULT_COMMAND = 'fd --type f --follow'
$env:FZF_CTRL_T_COMMAND = 'fd --type f --follow'
# Update notifications for LTS only
[System.Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'LTS')
