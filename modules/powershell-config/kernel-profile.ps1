$InformationPreference = "Continue";

. $HOME/.modules/powershell/pwsh-modules.ps1

if(Test-Path "$HOME/.profile.ps1") {
  . $HOME/.profile.ps1
}

# Vi style cursor
$stopwatch = [system.diagnostics.stopwatch]::StartNew()
if ($PSVersionTable.PSVersion.Major -ge 6) {
  $OnViModeChange = [scriptblock] {
    if ($args[0] -eq 'Command') {
      # Set the cursor to a blinking block.
      Write-Host -NoNewLine "`e[1 q"
    }
    else {
      # Set the cursor to a blinking line.
      Write-Host -NoNewLine "`e[5 q"
    }
  }
  Set-PSReadLineOption -ViModeIndicator Script -ViModeChangeHandler $OnViModeChange
}
$stopwatch.Stop(); Write-Verbose "`n-->> Troca automática de cursor demorou: $($stopwatch.ElapsedMilliseconds)"

# VI mode editing
$stopwatch = [system.diagnostics.stopwatch]::StartNew()
Set-PsReadLineOption -EditMode Vi
Set-PSReadlineOption -BellStyle None
$stopwatch.Stop(); Write-Verbose "`n-->> Ativar o modo VI demorou: $($stopwatch.ElapsedMilliseconds)"

# Enable prediction and increase history size
$stopwatch = [system.diagnostics.stopwatch]::StartNew()
try {
  $MaximumHistoryCount = 20000
  Set-PSReadlineOption -MaximumHistoryCount $MaximumHistoryCount
  Set-PSReadLineOption -PredictionSource History
  Set-PSReadLineOption -Colors @{ InlinePrediction = "#666699" }
  Set-PSReadLineKeyHandler -Chord "RightArrow" -Function ForwardWord
  Set-PSReadLineKeyHandler -Chord "End" -Function ForwardChar
}
catch {
  Install-Module -Force -AcceptLicense PSReadLine 
  Set-PSReadLineOption -PredictionSource History
  Set-PSReadLineOption -Colors @{ InlinePrediction = "#666699" }
  Set-PSReadLineKeyHandler -Chord "RightArrow" -Function ForwardWord
  Set-PSReadLineKeyHandler -Chord "End" -Function ForwardChar
}
$stopwatch.Stop(); Write-Verbose "`n-->> Ativar predição demorou: $($stopwatch.ElapsedMilliseconds)"

# dotnet autocomplete
$stopwatch = [system.diagnostics.stopwatch]::StartNew()
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
  Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
    dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
  }
}
$stopwatch.Stop(); Write-Verbose "`n-->> Importação do autocomplete do dotnet demorou: $($stopwatch.ElapsedMilliseconds)"

$stopwatch = [system.diagnostics.stopwatch]::StartNew()
if (! ($env:CODE_FOLDER)) {
  if ( Test-Path "~/code") {
    Write-Verbose "`n->> code folder found on home. Setting CODE_FOLDER"
    $env:CODE_FOLDER = "~/code"
  }
  elseif ( Test-Path "~/git") {
    Write-Verbose "`n->> git folder found on home. Setting CODE_FOLDER"
    $env:CODE_FOLDER = "~/git"
  }
  elseif ( Test-Path "/Git") { 
    Write-Verbose "`n->> Git folder found on root. Setting CODE_FOLDER"
    $env:CODE_FOLDER = "/Git"
  }
}
$stopwatch.Stop(); Write-Verbose "`n-->> Definição da CODE_FOLDER demorou: $($stopwatch.ElapsedMilliseconds)"

# Definição de scripts padrões
$stopwatch = [system.diagnostics.stopwatch]::StartNew()
$cicdFolder = (
  fd "^CI-CD$" --type d --max-depth 2 --base-directory $env:CODE_FOLDER --absolute-path 2>$null |
  Where-Object { $_ -NotMatch 'code-scripts' } |
  Select-Object -First 1
)
if ($cicdFolder) {
  Write-Verbose "`n->> CI-CD folder found at $cicdFolder, adding Utilitarios and Scripts to PATH"
  $env:PATH = "$($cicdFolder)Utilitarios:$($cicdFolder)QuickStarts/Scripts:${env:PATH}"
}
if ( (Test-Path "$HOME/.cargo/bin") -and !($env:PATH.Contains("$HOME/.cargo/bin")) ) {
  Write-Verbose "`n->> Rust's cargo folder found and not added to PATH. Adding now"
  $env:PATH = "$HOME/.cargo/bin:${env:PATH}"
}
if ( (Test-Path "$HOME/.local/bin") -and !($env:PATH.Contains("$HOME/.local/bin")) ) {
  Write-Verbose "`n->> ~/.local/bin folder found and not added to PATH. Adding now"
  $env:PATH = "$HOME/.local/bin:${env:PATH}"
}
$stopwatch.Stop(); Write-Verbose "`n-->> Definição de caminho de scripts padrões demorou: $($stopwatch.ElapsedMilliseconds)"

$stopwatch = [system.diagnostics.stopwatch]::StartNew()
Write-Verbose "`n->> Setting Util functions"
function Update-Profile () {
  . $PROFILE.CurrentUserAllHosts
}

function Confirm-Action($Message) {
  $Question = 'Are you sure you want to continue?'
  $Choices = '&Yes', '&No'

  $Decision = $Host.UI.PromptForChoice($Message, $Question, $Choices, 1)
  Write-Output $Decision
}

function Clean-SwapFiles {
  $swapDirectory = '~/.local/share/nvim/site/swapfiles'
  If (Test-Path $swapDirectory) {
    Write-Information "Current swap files on $swapDirectory will be deleted"
    Remove-Item -Recurse -Force "$swapDirectory/*"
  }
}

function FuzzySearch-Item($dir = "$env:CODE_FOLDER") {
  $selectedLocation = (fd . --base-directory $dir --type f --follow | fzf)
  if($selectedLocation) {
    return "$dir/$selectedLocation"
  } else {
    return ""
  }
}
function FuzzySearch-Location($dir = "$env:CODE_FOLDER") {
  $selectedLocation = (fd . --base-directory $dir --type d --follow | fzf)
  if($selectedLocation) {
    return "$dir/$selectedLocation"
  } else {
    return ""
  }
}

function FuzzyGet-ChildItem($dir = "$env:CODE_FOLDER") {
  $selectedItem = (FuzzySearch-Location $dir)
  if ($selectedItem) {
    Get-ChildItem $selectedItem
  }
}

function FuzzyInvoke-Item($dir = "$env:CODE_FOLDER") {
  $selectedItem = (FuzzySearch-Item $dir)
  if ($selectedItem) {
    Invoke-Item $selectedItem
  }
}

function FuzzyInvoke-Expression($dir = "$env:CODE_FOLDER") {
  $selectedItem = (FuzzySearch-Item $dir)
  if ($selectedItem) {
    Invoke-Expression $selectedItem
  }
}

function FuzzyOpenOnCode-Location($dir = "$env:CODE_FOLDER") {
  $selectedItem = (FuzzySearch-Location $dir)
  if ($selectedItem) {
    code -r $selectedItem
    Set-Location $selectedItem
  }
}

function FuzzyOpenOnCode-Item($dir = "$env:CODE_FOLDER") {
  $selectedItem = (FuzzySearch-Item $dir)
  if ($selectedItem) {
    code $selectedItem
  }
}

function FuzzyOpenOnVisualStudio-Solution($dir = "$env:CODE_FOLDER") {
  $selectedItem = (fd sln --base-directory $dir --type f --follow | fzf)
  if ($selectedItem) {
    Invoke-Item ($selectedItem)
  }
}

function FuzzySet-Location($dir = "$env:CODE_FOLDER") {
  $selectedItem = (FuzzySearch-Location $dir)
  if ($selectedItem) {
    Set-Location $selectedItem
  }
}

function FuzzyRun-DotNet($dir = "$env:CODE_FOLDER") {
  $selectedItem = (FuzzySearch-Location $dir)
  if ($selectedItem) {
    Set-Location $selectedItem
  }
  dotnet watch run
}

function FuzzyRun-DotNetTest($dir = "$env:CODE_FOLDER") {
  $selectedItem = (FuzzySearch-Location $dir)
  if ($selectedItem) {
    Set-Location $selectedItem
  }
  dotnet watch test
}

function FuzzyStart-NPM($dir = "$env:CODE_FOLDER") {
  $selectedItem = (FuzzySearch-Location $dir)
  if ($selectedItem) {
    Set-Location $selectedItem
  }
  Start-Npm
}

function FuzzyInvoke-History() {
  $selectedItem = (Get-History | Select-Object CommandLine | fzf)
  if ($selectedItem) {
    Invoke-Expression $selectedItem
  }
}

function FuzzyCopy-History() {
  $selectedItem = (Get-History | Select-Object CommandLine | fzf)
  if ($selectedItem) {
    $selectedItem | clip
  }
}

function GitFuzzySearch-Branch() {
  return git branch -a | Foreach-Object { $_.Replace('*', '').Trim() } | fzf
}

function GitFuzzyCheckout-Branch() {
  $selectedBranch = (GitFuzzySearch-Branch)
  if ($selectedBranch) {
    if ($selectedBranch.StartsWith("remotes/origin/")) {
      $selectedBranch = $selectedBranch.Replace("remotes/origin/", "")
    }
    git checkout $selectedBranch
  }
}

function GitFuzzyAdd-File() {
  $fileToAdd = (GitList-ModifiedFiles)
  if ($fileToAdd) {
    & git add $fileToAdd
  }
}

function GitFuzzyGet-History($dir = ".") {
  $fileToGetHistory = (FuzzyGet-ChildItem $dir)
  if ($fileToGetHistory) {
    & git history --follow -- $fileToGetHistory
  }
}

function GitFuzzyReset-File() {
  $selectedItem = (GitList-ModifiedFiles)
  if ($selectedItem -and (Test-Path $selectedItem)) {
    git reset $selectedItem
  }
}

function GitFuzzyCheckout-File($branch = "", $dir = ".") {
  $selectedItem = (FuzzySearch-Item $dir)
  if ($selectedItem -and (Test-Path $selectedItem)) {
    git checkout --force $branch -- $selectedItem
  }
}

function GitFuzzyDiff-File($branch = "master", $dir = ".") {
  $selectedItem = (FuzzySearch-Item $dir)
  if ($selectedItem -and (Test-Path $selectedItem)) {
    git diff $branch HEAD -- $selectedItem
  }
}

function GitUpdate-Branch($branch = "homolog") {
  git checkout $branch
  git merge -
  gitpu
  gitc-
}

function GitUpdate-Homolog($branch = "homolog") {
  git checkout $branch
  git merge -
  gitpu
  gitc-
}

function Git-Commit() {
  git commit
}

function Git-AmendCommit() {
  git commit --amend
}

function Git-AddDirectory() {
  git add .
}

function Git-AddAll() {
  git add --all
}

function Git-Pull() {
  git pull
}

function Git-Fetch() {
  git fetch
}

function Git-Undo() {
  git checkout --force -- .
  git clean -fd
}

function Git-Reset() {
  git reset
}

function Git-History() {
  git log --oneline --graph --pretty=format:'%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s' --date=short --author-date-order
}

function GitAdd-Untracked() {
  git ls-files -o --exclude-standard | Foreach-Object { git add $_ }
}

function GitIgnoreLocally-File([string] $File) {
  if(!($File)) {
    $File = GitList-ModifiedFiles;

    if(!($File)) {
      $File = '.';
    }
  }

  git update-index --assume-unchanged $File
}

function GitUndoLocallyIgnored-File([string] $File) {
  if(!($File)) {
    $File = FuzzyGet-ChildItem;

    if(!($File)) {
      $File = '.';
    }
  }

  git update-index --no-assume-unchanged $File
}

function Start-DotnetWatch([String]$LaunchProfile, [Switch]$SkipAutoUrls) {
  if(($env:DOTNET_SKIP_AUTO_URLS) -or ($SkipAutoUrls) -or !(Test-Path "./Properties/launchSettings.json") ) {
    Write-Verbose "Skipping auto exposing URLs"
    & dotnet watch run
    return;
  }

  if(!($LaunchProfile)) {
    $LaunchProfile = (Get-Item $PWD).Name
    Write-Verbose "No Profile informed. Using $LaunchProfile as Profile"
  }
  $LaunchSettings = Get-Content "./Properties/launchSettings.json" | ConvertFrom-Json
  $ApplicationUrls = $LaunchSettings.profiles.$LaunchProfile.applicationUrl

  if($ApplicationUrls -and $ApplicationUrls -match "0.0.0.0") {
    Write-Verbose "Running with the following URLs (Based on ./Properties/launchSettings.json): $ApplicationUrls"
    dotnet watch run
  }
  if($ApplicationUrls) {
    $ExposedUrls = $ApplicationUrls.Replace("localhost", "0.0.0.0")
    Write-Verbose "Running with the following URLs (Based on ./Properties/launchSettings.json and overriden to be accessible from outside the container): $ExposedUrls"
    dotnet watch run -- --urls="$ExposedUrls"
  } else {
    Write-Verbose "No applicationUrl detected on profile. Skipping auto exposing URLs"
    dotnet watch run
  }
}

function Start-DotnetWatchAPI([int[]]$HttpPorts, [int[]]$HttpsPorts) {
  $Urls += @($HttpPorts | Foreach-Object { "http://0.0.0.0:$_" })
  $Urls += @($HttpsPorts | Foreach-Object { "https://0.0.0.0:$_" })
  $FormattedUrls = [System.String]::Join(";", $Urls)
  Write-Verbose "Running with the following URLs: $FormattedUrls"
  & dotnet watch run -- --urls="$FormattedUrls"
}

function Test-DotnetWatch() {
  # Check if jq is available
  if (Get-Command jq -ErrorAction SilentlyContinue) {
    # Use fd to find appsettings.test.json with depth 2
    $appSettingsFile = & fd -t f --max-depth 2 '^appsettings\.test\.json$' 2>$null | Select-Object -First 1

    if ($appSettingsFile) {
      # Use jq to check if TipoDeProvedorDeContextoPorContexto is PostgresqlViaBaseLocal
      $providerType = & jq -r '.ConfiguracaoDoTeste.TipoDeProvedorDeContextoPorContexto.Contexto' $appSettingsFile 2>$null
      if ($providerType -eq "PostgresqlViaBaseLocal") {
        Write-Verbose "PostgreSQL provider detected, starting PostgreSQL container if needed..."
        Start-PostgresqlDockerContainer
      } else {
        Write-Verbose "appsettings.test.json is not using PostgresqlViaBaseLocal, so skipping postgres container"
      }
    } else {
      Write-Verbose "No appsettings.test.json file found"
    }
  } else {
    Write-Verbose "jq not available"
  }

  &dotnet watch test
}

function Start-Dotnet() {
  &dotnet run
}

function Test-Dotnet() {
  &dotnet test
}

function New-DotnetEFMigration($migrationName) {
  &dotnet ef migrations add $migrationName
}

function Update-DotnetEFDatabase($migrationName = $null) {
  &dotnet ef database update $migrationName
}

function Start-CargoWatch() {
  &cargo watch -x run
}

function Start-Npm() {
  if(Test-Path "./angular.json") {
    Write-Verbose "Angular project detected. Running watch with localhost exposed on 4200 so it can be accessed outside the container"
    & npm start -- --host 0.0.0.0
  } else {
    Write-Verbose "No Angular project detected. Running normal npm start"
    & npm start
  }
}

function Start-Yarn() {
  &yarn start
}

function ConvertFrom-Base64 {
    <#
    .SYNOPSIS
        Converts a base64 encoded string back to its original format.
    
    .DESCRIPTION
        This function takes a base64 encoded string and decodes it back to the original data.
        It can return the result as a string (UTF-8 decoded) or as raw bytes.
    
    .PARAMETER Base64String
        The base64 encoded string to decode.
    
    .PARAMETER AsBytes
        Switch parameter. If specified, returns the decoded data as a byte array.
        If not specified, returns the decoded data as a UTF-8 string.
    
    .EXAMPLE
        ConvertFrom-Base64String -Base64String "SGVsbG8gV29ybGQ="
        Returns: "Hello World"
    
    .EXAMPLE
        ConvertFrom-Base64String -Base64String "SGVsbG8gV29ybGQ=" -AsBytes
        Returns: [72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100]
    
    .EXAMPLE
        "VGhpcyBpcyBhIHRlc3Q=" | ConvertFrom-Base64String
        Returns: "This is a test"
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Base64String,
        
        [Parameter(Mandatory = $false)]
        [switch]$AsBytes
    )
    
    process {
        try {
            # Remove any whitespace or line breaks that might be in the base64 string
            $cleanBase64 = $Base64String.Trim() -replace '\s+', ''
            
            # Convert from base64 to byte array
            $decodedBytes = [System.Convert]::FromBase64String($cleanBase64)
            
            if ($AsBytes) {
                # Return as byte array
                return $decodedBytes
            } else {
                # Convert bytes to UTF-8 string
                $decodedString = [System.Text.Encoding]::UTF8.GetString($decodedBytes)
                return $decodedString
            }
        }
        catch [System.FormatException] {
            Write-Error "Invalid base64 string format: $Base64String"
            return $null
        }
        catch {
            Write-Error "Error decoding base64 string: $($_.Exception.Message)"
            return $null
        }
    }
}

function ConvertTo-Base64 {
    <#
    .SYNOPSIS
        Converts a string or byte array to a base64 encoded string.
    
    .DESCRIPTION
        This function takes a plain text string or byte array and encodes it as a base64 string.
        Supports different text encodings for string input.
    
    .PARAMETER InputString
        The plain text string to encode to base64.
    
    .PARAMETER InputBytes
        The byte array to encode to base64.
    
    .PARAMETER Encoding
        The text encoding to use when converting string to bytes.
        Valid values: UTF8 (default), ASCII, Unicode, UTF32, UTF7
    
    .EXAMPLE
        ConvertTo-Base64String -InputString "Hello World"
        Returns: "SGVsbG8gV29ybGQ="
    
    .EXAMPLE
        ConvertTo-Base64String -InputString "This is a test" -Encoding ASCII
        Returns: "VGhpcyBpcyBhIHRlc3Q="
    
    .EXAMPLE
        "Hello World" | ConvertTo-Base64String
        Returns: "SGVsbG8gV29ybGQ="
    
    .EXAMPLE
        $bytes = [byte[]]@(72, 101, 108, 108, 111)
        ConvertTo-Base64String -InputBytes $bytes
        Returns: "SGVsbG8="
    #>
    
    [CmdletBinding(DefaultParameterSetName = 'String')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0, ParameterSetName = 'String')]
        [AllowEmptyString()]
        [string]$InputString,
        
        [Parameter(Mandatory = $true, ParameterSetName = 'Bytes')]
        [byte[]]$InputBytes,
        
        [Parameter(Mandatory = $false, ParameterSetName = 'String')]
        [ValidateSet('UTF8', 'ASCII', 'Unicode', 'UTF32', 'UTF7')]
        [string]$Encoding = 'UTF8'
    )
    
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'String') {
                # Convert string to bytes using specified encoding
                switch ($Encoding) {
                    'UTF8' { $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString) }
                    'ASCII' { $bytes = [System.Text.Encoding]::ASCII.GetBytes($InputString) }
                    'Unicode' { $bytes = [System.Text.Encoding]::Unicode.GetBytes($InputString) }
                    'UTF32' { $bytes = [System.Text.Encoding]::UTF32.GetBytes($InputString) }
                    'UTF7' { $bytes = [System.Text.Encoding]::UTF7.GetBytes($InputString) }
                    default { $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString) }
                }
            } else {
                # Use provided byte array
                $bytes = $InputBytes
            }
            
            # Convert bytes to base64 string
            $base64String = [System.Convert]::ToBase64String($bytes)
            return $base64String
        }
        catch {
            Write-Error "Error encoding to base64: $($_.Exception.Message)"
            return $null
        }
    }
}

function GitList-ModifiedFiles() {
  $selectedFile = (git status --short | fzf)
  if ($selectedFile) {
    $selectedFile = $selectedFile.Trim().Replace('  ', ' ').Split(' ')[1]
    return $selectedFile
  }
}

function GitPush-UpstreamBranch() {
  & git push --set-upstream origin (git branch --show-current)
}

function GitDiff-UnstagedChanges() {
  & git diff --ignore-all-space --ignore-blank-lines --ignore-space-at-eol
}

function GitDiff-StagedChanges() {
  & git diff --cached --ignore-all-space --ignore-blank-lines --ignore-space-at-eol
}

function GitDiff-VerboseUnstagedChanges() {
  & git diff
}

function GitDiff-VerboseStagedChanges() {
  & git diff --cached
}

function GitCheckout-Previous() {
  & git checkout -
}

function GitCheckout-Branch([String] $branch) {
  & git checkout -b $branch
}

function GitGet-History() {
  & git log --oneline --graph --pretty=format:'%C(yellow)%h %Cred%ad %Cblue%an%Cgreen%d %Creset%s' --date=short --author-date-order
}

function FuzzyFocus-RunningApplication() {
  $runningApplications = Get-Process | Where-Object { $_.mainwindowhandle -ne 0 }
  $chosenApplicationInput = ($runningApplications | Select-Object name, mainwindowtitle | fzf)
  Write-Verbose "Opção escolhida: $chosenApplicationInput"
  $chosenApplications = ($runningApplications | Where-Object { $chosenApplicationInput -match $_.name }) | Where-Object { $chosenApplicationInput -match $_.mainwindowtitle }
  Write-Verbose "Aplicações que encaixam: $chosenApplications"
  $chosenApplication = $chosenApplications | Select-Object -first 1 | Select-Object -ExpandProperty mainwindowtitle
  Write-Verbose "Aplicação final: $chosenApplication"
  $wshell = New-Object -ComObject wscript.shell
  $wshell.AppActivate($chosenApplication)
}

function Update-SessionPath () {
  $env:PathBackup = [System.Environment]::GetEnvironmentVariable("PathBackup", "User")
  $currentPathMerge = "$([System.Environment]::GetEnvironmentVariable("PATH", "Machine"));$([System.Environment]::GetEnvironmentVariable("Path", "User"))"
  $env:Path = $currentPathMerge
}

function Get-PathEntries() {
  Update-SessionPath
  $env:Path.Split(";") |
  Sort-Object |
  Get-Unique
}

function Add-PathEntry($NewEntry) {
  if (! $NewEntry) {
    Write-Error "Cancelling Add-PathEntry because no new entry was informed" -ErrorAction Stop
  }

  $NewEntry = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($NewEntry)
  $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ($CurrentUserPath.Split(";").Contains($NewEntry)) {
    Write-Information "`n ->> O caminho solicitado ($NewEntry) já consta no Path"
    return
  }
  $UpdatedUserPath = "$CurrentUserPath;$NewEntry"
  Write-Information "`n ->> New Path: ($UpdatedUserPath)"
  [Environment]::SetEnvironmentVariable("PathBackup", $CurrentUserPath, "User")
  [Environment]::SetEnvironmentVariable("Path", $UpdatedUserPath, "User")
  Update-SessionPath
}

function Update-PathEntries($PreviousText, $SubstituteText) {
  if (!$PreviousText -Or !$SubstituteText ) {
    Write-Error "Cancelling Update-PathEntries because either PreviousText or SubstituteText was not informed" -ErrorAction Stop
  }

  $PreviousText = $PreviousText.Replace("/", "\")
  $SubstituteText = $SubstituteText.Replace("/", "\")
  $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $UpdatedEntries = ($CurrentUserPath.Split(";") |
    Sort-Object |
    Get-Unique |
    Foreach-Object { $_.Replace($PreviousText, $SubstituteText) })
  $NewPath = [string]::Join(";", $UpdatedEntries)
  Write-Information "`n ->> New Path: ($NewPath)"
  [Environment]::SetEnvironmentVariable("PathBackup", $CurrentUserPath, "User")
  [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
  Update-SessionPath
}

function Remove-PathEntries($PathToBeRemoved) {
  if (! $PathToBeRemoved) {
    Write-Error "Cancelling Remove-PathEntries because no PathToBeRemoved was informed" -ErrorAction Stop
  }

  $PathToBeRemoved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PathToBeRemoved)
  if ($PathToBeRemoved -eq $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("/")) {
    Write-Error "Cannot remove all the entries from ($PathToBeRemoved). Try a more specific path" -ErrorAction Stop
  }

  $CurrentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $CurrentEntries = $CurrentUserPath.Split(";") |
  Sort-Object |
  Get-Unique
  $UpdatedEntries = ( $CurrentEntries |
    Where-Object { ! ($_.StartsWith($PathToBeRemoved)) } )

  $entriesToBeRemoved = $CurrentEntries |
  Where-Object { $UpdatedEntries -notcontains $_ }
  if ($entriesToBeRemoved) {
    $confirmed = Confirm-Action "Entries to be removed: ( $([String]::Join("; ", $entriesToBeRemoved)) )"
  }
  else {
    Write-Error "No entries found" -ErrorAction Stop
  }

  Write-Verbose "Confirmation Result = ${confirmed}"
  if ($confirmed) {
    Write-Error "Cancelled by user" -ErrorAction Stop
  }

  $NewPath = [string]::Join(";", $UpdatedEntries)
  Write-Information "`n ->> Number of entries: {$($UpdatedEntries.Length)} New Path: ($NewPath)"
  [Environment]::SetEnvironmentVariable("PathBackup", $CurrentUserPath, "User")
  [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
  Update-SessionPath
}

function Stop-ProcessByName($processName) {
  Stop-Process -ProcessName $processName
}

function Copy-NewGuidToClipboard() {
  (New-Guid).Guid | clip
}

function Create-SshKey($SshKeyFolder = "$HOME/.ssh", $Comment = "$(whoami)@$env:HOSTNAME") {
  $sshKey = "$SshKeyFolder/id_rsa"
  if( !(Test-Path $sshKey) ) {
    ssh-keygen -C "$Comment"
  } else {
    Write-Information "There is already a ssh-key there"
  }
}

function Add-SshKey($SshKeyFolder = "$HOME/.ssh", $SshKeyFile = "id_rsa") {
  $sshKey = "$SshKeyFolder/$SshKeyFile"
  if ( (!$env:SSH_AUTH_SOCK -or !$env:SSH_AGENT_PID) -and (Test-Path $sshKey) ) {
    Write-Verbose "`n->> Adding SSH key"
    $sshAgent = ssh-agent;
    $env:SSH_AUTH_SOCK = $sshAgent[0].Split("=").Split(";")[1]
    $env:SSH_AGENT_PID = $sshAgent[1].Split("=").Split(";")[1]
    ssh-add $sshKey
  }
  else {
    Write-Information "`n->> SSH Agent already added"
  }
  Write-Information "`n->> Agent PID: $env:SSH_AGENT_PID"
}

function Start-DotnetWatchRunDockerContainer($Version = "3.1", $Port = "5001") {
  docker container run --rm -v ${pwd}:/app/ -w /app -p ${Port}:${Port} -it mcr.microsoft.com/dotnet/sdk:$Version dotnet watch run --urls https://0.0.0.0:${Port}
}

function New-DotnetCommandDockerContainer($Version = "3.1", [String]$Command) {
  docker container run --rm -v ${pwd}:/app/ -w /app -it mcr.microsoft.com/dotnet/sdk:$Version dotnet ($Command -split " ")
}

function Start-NpmStartDockerContainer($Version = "lts-alpine", $Port = "4200", $Parameters = "--host 0.0.0.0") {
  docker container run --rm -v ${pwd}:/app/ -w /app -p 4200:4200 -it node:$Version npm start -- (${Parameters} -split " ")
}

function Start-NpmInstallDockerContainer($Version = "lts-alpine") {
  docker container run --rm -v ${pwd}:/app/ -w /app -it node:$Version npm install
}

function Start-SqlServerDockerContainer($Version = "2019-latest", [switch]$Interactive) {
  if (!($env:ROOTLESS_DOCKER) -and (Get-Command sudo -ErrorAction SilentlyContinue)) {
    $Command = 'sudo docker';
    $UserFlag = @();
  } else {
    $Command = 'docker';
    $UserFlag = @('-u', '0:0');  # Run as root in rootless Docker (maps to host user)
  }
  if ($Interactive) {
    & $Command run @UserFlag -e "TZ=America/Sao_Paulo" -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=L0c4lD3v!" -p 1433:1433 -it --rm -v localdb:/var/opt/mssql/data/ --memory=2g --memory-swap=0 --name mssql mcr.microsoft.com/mssql/server:$version
  }
  else {
    & $Command run @UserFlag -e "TZ=America/Sao_Paulo" -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=L0c4lD3v!" -p 1433:1433 -d --rm -v localdb:/var/opt/mssql/data/ --memory=2g --memory-swap=0 --name mssql mcr.microsoft.com/mssql/server:$version
  }
}

function Start-PostgresqlDockerContainer($Version = "latest", [switch]$Interactive) {
  if (!($env:ROOTLESS_DOCKER) -and (Get-Command sudo -ErrorAction SilentlyContinue)) {
    $Command = 'sudo docker';
  } else {
    $Command = 'docker';
  }

  # Check if postgres container is already running
  $runningContainer = & $Command ps --filter "name=postgres" --format "{{.Names}}" 2>$null
  if ($runningContainer -eq "postgres") {
    Write-Verbose "PostgreSQL container is already running"
    return
  }

  if ($Interactive) {
    & $Command run -e "TZ=America/Sao_Paulo" -e "POSTGRES_PASSWORD=L0c4lD3v!" -e "POSTGRES_USER=postgres" -p 5432:5432 -it --rm -v postgresdb:/var/lib/postgresql --name postgres postgres:$version
  }
  else {
    & $Command run -e "TZ=America/Sao_Paulo" -e "POSTGRES_PASSWORD=L0c4lD3v!" -e "POSTGRES_USER=postgres" -p 5432:5432 -d --rm -v postgresdb:/var/lib/postgresql --name postgres postgres:$version
  }
}

function Set-LocalContextDatabase($DatabaseName = "contexto", $ContextName = "Contexto", $DataSourceName = "::1", $UserId = "sa", $Password = "L0c4lD3v!") {
  if (!$DatabaseName) {
    $env:ConnectionStrings__Contexto = $null
  }
  else {
    [Environment]::SetEnvironmentVariable("ConnectionStrings__$ContextName", "Data Source=$DataSourceName;Initial Catalog=$DatabaseName;Persist Security Info=True;User Id=$UserId;Password=$Password;encrypt=false")
  }
}

function Exit-Session() {
  exit
}

function Set-AutoNodeVersion() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if ( !(Get-Command node -ErrorAction SilentlyContinue) ) {
    Write-Warning "`n->> No default node version detected, setting as LTS"
    nvs use lts
  }
  Write-Verbose "`n->> Setting nvs auto on"
  nvs auto on
  $stopwatch.Stop(); Write-Information "`n-->> Definição de versão padrão do NVS demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Run-CodeFolderScripts() {
  $CodeFolder = "$HOME/code/"
  if(!$PWD.Path.StartsWith($CodeFolder)) {
    Write-Verbose "`n->> This folder is not a ~/code subfolder. Skipping"
    return
  }
    
  $CurrentFolder = $PWD.Path.Replace($CodeFolder, "").Replace("AT/", "").Split("/")[0]
  $CodeScriptFolder = "$HOME/code/code-scripts/$CurrentFolder"
  if(!(Test-Path $CodeScriptFolder)) {
    Write-Verbose "`n->> This folder does not have a scripts folder on ($CodeScriptFolder). Skipping"
    return
  }

  $PowerShellScriptsForThisFolder = Get-ChildItem $CodeScriptFolder -Filter "*.ps1"
  if(!$PowerShellScriptsForThisFolder) {
    Write-Verbose "`n->> No PowerShell script found on $CodeScriptFolder"
  }

  foreach($Script in $PowerShellScriptsForThisFolder) {
    Write-Verbose "`n->> Invoking. $Script"
    . $Script
  }
}

function Get-PowerShellCoreDotNetVersion() {
  [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
}

function Build-DotnetProjectIfNeeded() {
  if ((Test-Path "*.sln") -and !(Test-Path ".vs")) {
    Write-Verbose "Project not yet built. Building now and creating .vs folder as a way to skip build next time..."
    & dotnet build
    New-Item -Type Directory .vs
  } else {
    Write-Verbose "Project already built."
  }
}

function Install-NpmIfNeeded() {
  if ((Test-Path "package.json") -and !(Test-Path "node_modules")) {
    & npm install
  }
}

function Open-Files($Path = '.') {
  if (Get-Command 'nautilus' -ErrorAction SilentlyContinue) {
    nautilus $Path
  } else {
    explorer $Path
  }

}

$stopwatch.Stop(); Write-Verbose "`n-->> Definição de functions demorou: $($stopwatch.ElapsedMilliseconds)"

$stopwatch = [system.diagnostics.stopwatch]::StartNew()
Write-Debug "`n->> Setting Aliases"

if ( !(Test-Path "/usr/bin/clip") -and !(Test-Path "$HOME/.local/bin/clip") ) {
  New-Alias -Force clip Set-Clipboard
}

New-Alias -Force guid Copy-NewGuidToClipboard

New-Alias -Force fgi FuzzySearch-Item
New-Alias -Force fgl FuzzySearch-Location
New-Alias -Force fsi FuzzySearch-Item
New-Alias -Force fsl FuzzySearch-Location
New-Alias -Force fcode FuzzyOpenOnCode-Item
New-Alias -Force fcoder FuzzyOpenOnCode-Location
New-Alias -Force fvs FuzzyOpenOnVisualStudio-Solution
New-Alias -Force fii FuzzyInvoke-Item
New-Alias -Force fiex FuzzyInvoke-Expression
New-Alias -Force fh FuzzyInvoke-History
New-Alias -Force fdfzf FuzzySearch-Item
New-Alias -Force fcd FuzzySet-Location
New-Alias -Force fdotnet FuzzyRun-DotNet
New-Alias -Force fdotnettest FuzzyRun-DotNetTest
New-Alias -Force fdr FuzzyRun-DotNet
New-Alias -Force fdt FuzzyRun-DotNetTest
New-Alias -Force fnpm FuzzyStart-NPM
New-Alias -Force fls FuzzyGet-ChildItem
New-Alias -Force fcdw FuzzySearch-WorkSpace

New-Alias -Force git-branchf GitFuzzySearch-Branch
New-Alias -Force git-checkoutf GitFuzzyCheckout-Branch

New-Alias -Force gitb GitFuzzySearch-Branch
New-Alias -Force gitco GitFuzzyCheckout-Branch
New-Alias -Force gitdf GitDiff-UnstagedChanges
New-Alias -Force gitdff GitDiff-VerboseUnstagedChanges
New-Alias -Force gitdfc GitDiff-StagedChanges
New-Alias -Force gitdffc GitDiff-VerboseStagedChanges
New-Alias -Force gitff GitList-ModifiedFiles
New-Alias -Force gitpu GitPush-UpstreamBranch
New-Alias -Force gitc- GitCheckout-Previous
New-Alias -Force gitcb GitCheckout-Branch
New-Alias -Force gith GitGet-History
New-Alias -Force gitfa GitFuzzyAdd-File
New-Alias -Force gitfr GitFuzzyReset-File
New-Alias -Force gitfc GitFuzzyCheckout-File
New-Alias -Force gitfdf GitFuzzyDiff-File
New-Alias -Force gitc Git-Commit
New-Alias -Force gitam Git-AmendCommit
New-Alias -Force gita Git-AddDirectory
New-Alias -Force gitaa Git-AddAll
New-Alias -Force gitf Git-Fetch
New-Alias -Force gitpl Git-Pull
New-Alias -Force gitub GitUpdate-Branch
New-Alias -Force gitu Git-Undo
New-Alias -Force gitr Git-Reset
New-Alias -Force gitfh GitFuzzyGet-History
New-Alias -Force gitau GitAdd-Untracked
New-Alias -Force gitif GitIgnoreLocally-File

New-Alias -Force stop Stop-Process
New-Alias -Force tasks Get-Process
New-Alias -Force whereis Get-Command
New-Alias -Force rpi Invoke-Raspberry
New-Alias -Force adv Restart-WithAdvancedParameters


New-Alias -Force dwr Start-DotnetWatch
New-Alias -Force dwt Test-DotnetWatch
New-Alias -Force dr Start-Dotnet
New-Alias -Force dt Test-Dotnet
New-Alias -Force dnetm New-DotnetEFMigration
New-Alias -Force dnetu New-DotnetEFMigration
New-Alias -Force slc Set-LocalContextDatabase

New-Alias -Force cwr Start-CargoWatch

New-Alias -Force ddwr Start-DockerDotnetWatchRun

New-Alias -Force poshgit Import-PoshGit
New-Alias -Force psgit Import-PoshGit
New-Alias -Force psomp Import-OhMyPoshOnLinux
New-Alias -Force omp Import-OhMyPoshOnLinux
New-Alias -Force psfzf Import-PsFzf
New-Alias -Force psaws Import-PsAWS
New-Alias -Force psnvm Import-PsNvm
New-Alias -Force psdocker Import-DockerCompletion

New-Alias -Force files Open-Files
New-Alias -Force npms Start-Npm
New-Alias -Force yarns Start-Yarn
New-Alias -Force :q Exit-Session
$stopwatch.Stop(); Write-Verbose "`n-->> Definição de aliases do kernel demorou: $($stopwatch.ElapsedMilliseconds)"


$stopwatch = [system.diagnostics.stopwatch]::StartNew()
$env:FZF_DEFAULT_COMMAND = 'fd --type f --follow'
$env:FZF_CTRL_T_COMMAND = 'fd --type f --follow'
Write-Verbose "`n->> Set update notifications to LTS only"
[System.Environment]::SetEnvironmentVariable('POWERSHELL_UPDATECHECK', 'LTS')
$stopwatch.Stop(); Write-Verbose "`n-->> Definir variáveis de ambiente demorou: $($stopwatch.ElapsedMilliseconds)"
