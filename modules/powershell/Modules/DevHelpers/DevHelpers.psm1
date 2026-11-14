# The profile's helper functions and their aliases, autoloaded on first use: pwsh
# finds them through FunctionsToExport/AliasesToExport in DevHelpers.psd1, so a
# shell start no longer pays to parse ~1200 lines and run ~85 New-Alias calls
# (~100ms) for commands most sessions never type. The profile puts
# ~/.modules/powershell/Modules on PSModulePath (kernel-profile.ps1).
#
# Adding a function or alias here means listing it in DevHelpers.psd1 too:
# autoload only knows what the manifest names. What has to run at startup, or be
# dot-sourced into the global scope (Run-CodeFolderScripts), stays in the profile.


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
  return git branch -a | Foreach-Object { $_.Substring(2) } | fzf
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
  Invoke-GitWithSshKey -GitArgs (@('pull') + $args)
}

function Git-Fetch() {
  Invoke-GitWithSshKey -GitArgs (@('fetch') + $args)
}

# Runs a git command that reaches a remote -- gitf, gitpl, gitpu -- and, when
# what turned it away was a key the agent does not hold, unlocks that key in
# this machine's shared agent (Add-SshKey) and runs it again.
#
# git runs with ssh in BatchMode, so a missing key fails at once rather than
# leaving ssh to ask for some passphrase on its own. A failure is put down to
# the key only when a quiet ls-remote of the same remote is refused by ssh too
# (Test-GitSshRefused): a merge conflict or a rejected push is left as it is,
# and never costs a passphrase.
#
# The key to unlock is the one Find-SshKey.sh (git-radar's) finds the server
# accepts among those this machine would try. When it cannot tell, or that key
# did not do, every other key in ~/.ssh with a .pub beside it is tried in turn
# -- the one the profile unlocks at startup first (Get-DefaultSshKeyFile) --
# skipping the ones the agent already holds, until git gets through.
#
# -Remote is the remote the command reaches: by default the current branch's,
# else origin. Ends with git's exit code in $LASTEXITCODE.
function Invoke-GitWithSshKey([string[]] $GitArgs, [string] $Remote) {
  if (!$Remote) {
    $branch = git branch --show-current 2> $null
    if ($branch) { $Remote = git config "branch.$branch.remote" 2> $null }
    if (!$Remote) { $Remote = 'origin' }
  }
  # Only an ssh remote has a key to unlock: https and local paths run as they are.
  $url = git remote get-url $Remote 2> $null
  $isSsh = $url -and ($url -match '^ssh://' -or ($url -notmatch '://' -and $url -match '^[^/:]+:'))
  if (!$isSsh) {
    git @GitArgs
    return
  }
  # BatchMode on top of whatever ssh git would have run.
  $sshCommand = if ($env:GIT_SSH_COMMAND) { $env:GIT_SSH_COMMAND } else { git config core.sshCommand }
  if (!$sshCommand) { $sshCommand = 'ssh' }
  $previous = $env:GIT_SSH_COMMAND
  $env:GIT_SSH_COMMAND = "$sshCommand -o BatchMode=yes"
  try {
    git @GitArgs
    $code = $LASTEXITCODE
    if ($code -eq 0 -or !(Test-GitSshRefused $Remote)) { return }
    $root = git rev-parse --show-toplevel
    $found = sh "$HOME/.modules/git-radar/scripts/Find-SshKey.sh" $root $Remote 2> $null
    $tried = @()
    foreach ($key in @($found) + @(Get-SshKeyCandidates)) {
      if (!$key -or $tried -contains $key) { continue }
      $tried += $key
      Write-Host "`n->> $Remote turned the ssh key away: unlocking $key" -ForegroundColor Yellow
      Add-SshKey -SshKeyFolder (Split-Path $key) -SshKeyFile (Split-Path $key -Leaf)
      git @GitArgs
      $code = $LASTEXITCODE
      if ($code -eq 0 -or !(Test-GitSshRefused $Remote)) { return }
    }
    Write-Host "`n->> No ssh key here gets into $Remote" -ForegroundColor Red
  }
  finally {
    $env:GIT_SSH_COMMAND = $previous
    $global:LASTEXITCODE = $code
  }
}

# Whether <Remote> turns this machine away for want of an ssh key: a quiet
# ls-remote, under the caller's BatchMode ssh, refused with ssh's publickey
# error rather than failing for any other reason.
function Test-GitSshRefused($Remote) {
  $out = git ls-remote $Remote HEAD 2>&1 | Out-String
  return $LASTEXITCODE -ne 0 -and $out -match 'Permission denied|publickey'
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
    return
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
  Invoke-GitWithSshKey -GitArgs @('push', '--set-upstream', 'origin', (git branch --show-current)) -Remote origin
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

function GitGet-RecursiveCommitHistory(
  [String]$Path = ".",
  [String]$Name = "Thomaz Moura",
  [DateTime]$StartDate = (Get-Date -Day 1).AddMonths(-1),
  [DateTime]$EndDate = (Get-Date)
) {
  $StartDateFormatted = $StartDate.ToString("yyyy-MM-dd")
  $EndDateFormatted = $EndDate.ToString("yyyy-MM-dd")

  Get-ChildItem -Path $Path -Directory | ForEach-Object {
    $repoPath = $_.FullName
    $repoName = $_.Name

    if (Test-Path (Join-Path $repoPath ".git")) {
      Push-Location $repoPath
      try {
        git log --author="$Name" --after="$StartDateFormatted" --before="$EndDateFormatted" --format="%s|%ad" --date=short 2>$null |
          ForEach-Object {
            $parts = $_ -split '\|'
            if ($parts.Count -ge 2) {
              [PSCustomObject]@{
                Description = $parts[0]
                Date        = $parts[1]
                Repository  = $repoName
              }
            }
          }
      } finally {
        Pop-Location
      }
    }
  }
}

function Get-AzureDevOpsWorkItems([int]$Days = 31) {
  $wiql = @"
SELECT [System.Id], [System.Title], [System.State], [System.WorkItemType], [System.CreatedDate], [System.ChangedDate]
FROM workitems
WHERE [System.AssignedTo] = @Me
  AND [System.ChangedDate] >= @Today - $Days
ORDER BY [System.ChangedDate] DESC
"@

  $result = az boards query --wiql $wiql --output json 2>$null | ConvertFrom-Json

  $result | ForEach-Object {
    [PSCustomObject]@{
      Id          = $_.fields.'System.Id'
      Title       = $_.fields.'System.Title'
      State       = $_.fields.'System.State'
      Type        = $_.fields.'System.WorkItemType'
      CreatedDate = $_.fields.'System.CreatedDate'
      ChangedDate = $_.fields.'System.ChangedDate'
    }
  }
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

# The key the profile unlocks at startup, as a file name in <SshKeyFolder>:
# the one $env:SSH_KEY_FILE names, else the first key in the folder that has a
# .pub beside it. Nothing when there is neither.
function Get-DefaultSshKeyFile($SshKeyFolder = "$HOME/.ssh") {
  if ($env:SSH_KEY_FILE) { return $env:SSH_KEY_FILE }
  $pub = Get-ChildItem -Path $SshKeyFolder -Filter "*.pub" -File -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -First 1
  if ($pub) { return $pub.BaseName }
}

# Every key in <SshKeyFolder> with a .pub beside it that the agent does not
# hold, as paths: the startup key first (Get-DefaultSshKeyFile), then by name.
# A key is told apart by its public half, the .pub's type and key fields
# against each line of ssh-add -L.
function Get-SshKeyCandidates($SshKeyFolder = "$HOME/.ssh") {
  $loaded = @(ssh-add -L 2> $null) | ForEach-Object { ($_ -split ' ')[0..1] -join ' ' }
  $first = Get-DefaultSshKeyFile $SshKeyFolder
  Get-ChildItem -Path $SshKeyFolder -Filter "*.pub" -File -ErrorAction SilentlyContinue |
    Sort-Object @{ Expression = { $_.BaseName -ne $first } }, Name |
    Where-Object { [IO.File]::Exists("$SshKeyFolder/$($_.BaseName)") } |
    Where-Object { $loaded -notcontains (((Get-Content $_.FullName -TotalCount 1) -split ' ')[0..1] -join ' ') } |
    ForEach-Object { "$SshKeyFolder/$($_.BaseName)" }
}

function Add-SshKey($SshKeyFolder = "$HOME/.ssh", $SshKeyFile = $null) {
  # The key to add: the one asked for, else the profile's startup key.
  if (!$SshKeyFile) { $SshKeyFile = Get-DefaultSshKeyFile $SshKeyFolder }
  if (!$SshKeyFile) {
    Write-Information "`n->> No SSH key found in $SshKeyFolder"
    return
  }
  $sshKey = "$SshKeyFolder/$SshKeyFile"
  if (![IO.File]::Exists($sshKey)) {
    Write-Information "`n->> No SSH key at $sshKey"
    return
  }
  # This machine's shared agent, the one every pane uses (see
  # linux-profile.ps1): Unlock-SshAgent.sh starts it when it is not running and
  # asks for the key when it does not hold it. Panes asking at the same time
  # wait for the first one's password instead of each asking.
  $agentDir = "$HOME/.ssh/tmux-agent"
  $unlock = "$HOME/.modules/tmux/scripts/Unlock-SshAgent.sh"
  if ([IO.File]::Exists($unlock)) {
    sh $unlock $sshKey
  }
  if ([IO.File]::Exists("$agentDir/agent.sock") -and [IO.File]::Exists("$agentDir/agent.pid")) {
    $env:SSH_AUTH_SOCK = "$agentDir/agent.sock"
    $env:SSH_AGENT_PID = [IO.File]::ReadAllText("$agentDir/agent.pid").Trim()
  }
  else {
    # No shared agent to be had -- no ~/.modules, or no socket where ~/.ssh
    # lives: an agent of this shell's own, as before there was a shared one.
    Write-Verbose "`n->> Adding SSH key to a private agent"
    $sshAgent = ssh-agent;
    $env:SSH_AUTH_SOCK = $sshAgent[0].Split("=").Split(";")[1]
    $env:SSH_AGENT_PID = $sshAgent[1].Split("=").Split(";")[1]
    ssh-add $sshKey
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

  # Check if mssql container is already running
  $runningContainer = & $Command ps --filter "name=mssql" --format "{{.Names}}" 2>$null
  if ($runningContainer -eq "mssql") {
    Write-Verbose "SQL Server container is already running"
    return
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

function Exit-Session() {
  exit
}

# Switches to the node version of the .node-version (or .nvmrc) in scope, or to
# LTS when there is none. Not run by the profile -- a prompt hook costs every
# shell, and most never touch node -- but by the pane commands that need node:
# the Copilot CLI and herdr, in modules/tmux/scripts/tmux-helpers.sh,
# modules/tmux/common.conf and modules/herdr/scripts/Start-Herdr.sh. NeoVim
# does not need it: its LSP servers and Copilot run on their own node.
function Use-NodeVersion() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  nvs use auto
  # With no version file and no `nvs link` default, `nvs use auto` leaves no
  # node on PATH at all.
  if ( !(Get-Command node -ErrorAction SilentlyContinue) ) {
    Write-Verbose "`n->> No .node-version in scope, using LTS"
    nvs use lts
  }
  $stopwatch.Stop(); Write-Verbose "`n-->> Definição de versão do NVS demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Get-PowerShellCoreDotNetVersion() {
  [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
}

function Build-DotnetProjectIfNeeded() {
  if ((Test-Path "*.sln") -and !(Test-Path ".vs")) {
    Write-Verbose "Project not yet built. Building now and creating .vs folder as a way to skip build next time..."
    & dotnet build
    # The .vs folder is a receipt for a *successful* build, not an attempted one.
    # Native command failures do not stop the script, so without this check a
    # build that died on a bad restore would still mark the project as done and
    # every later session would skip it - leaving the LSP without packages.
    if ($LASTEXITCODE -eq 0) {
      New-Item -Type Directory .vs | Out-Null
    } else {
      Write-Warning "dotnet build failed with exit code $LASTEXITCODE. Not creating .vs, so the build is retried next session."
    }
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

function Copy-CoPilotCommand() {
  param(
    [switch]$Resume,
    [Parameter(ValueFromRemainingArguments)]$remaining
  )
  nvs use latest
  $settings = Get-Content "$HOME/.claude/settings.json" | ConvertFrom-Json
  $allowTools = $settings.permissions.allow `
    | Where-Object { $_ -match '^Bash\(' } `
    | ForEach-Object { $_ -replace '^Bash\((.+)\)$', '--allow-tool ''shell($1)''' }
  $allowToolsStr = $allowTools -join ' '
  $resumeFlag = if ($Resume.IsPresent) { '--resume' } else { '' }
  $command = "copilot $allowToolsStr $resumeFlag $remaining; exit"
  Write-Verbose "Copying command to the clipboard: $command"
  $command | clip
}

function ConvertFrom-Jwt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$Token
    )

    process {
        $parts = $Token.Trim().Split('.')
        if ($parts.Count -lt 2) {
            Write-Error 'Not a JWT: expected at least two dot-separated segments.'
            return
        }

        $decode = {
            param([string]$Segment)
            $s = $Segment.Replace('-', '+').Replace('_', '/')
            switch ($s.Length % 4) {
                2 { $s += '==' }
                3 { $s += '=' }
                1 { throw 'Invalid base64url segment.' }
            }
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s))
        }

        [pscustomobject]@{
            Header  = & $decode $parts[0] | ConvertFrom-Json
            Payload = & $decode $parts[1] | ConvertFrom-Json
        }
    }
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
New-Alias -Force gitrh GitGet-RecursiveCommitHistory
New-Alias -Force adoswi Get-AzureDevOpsWorkItems

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
New-Alias -Force copylot Copy-CoPilotCommand
function New-HorizontalTmuxSession ($FirstPaneCommand="psgit", $SecondPaneCommand="") {
  $location = FuzzySearch-Location
	if($location) {
		Set-Location $location
		$currentDirectory = ($pwd.Path.Split("/") | Select-Object -Last 1)
		& tmux new-session `; `
			rename-session $currentDirectory `; `
			select-pane -t 0 `; `
			select-pane -T "NeoVim" `; `
			set -p '@pane_label' "NeoVim" `; `
			split-window -h -l 20% `; `
			select-pane -t 1 `; `
			select-pane -T "Terminal" `; `
			set -p '@pane_label' "Terminal" `; `
			send-keys "$SecondPaneCommand" C-m `; `
			split-window -v -l 50% `; `
			select-pane -t 2 `; `
			select-pane -T "Terminal" `; `
			set -p '@pane_label' "Terminal" `; `
			send-keys "$FirstPaneCommand" C-m `; `
			select-pane -t 1 `; `
			select-pane -T "Terminal" `; `
			set -p '@pane_label' "Terminal" `; `
			select-pane -t 0 `; `
			select-pane -T "NeoVim" `; `
			set -p '@pane_label' "NeoVim" `; `
			send-keys nvim C-m
	}
	Write-Information "Cancelled by user"
}

function New-HorizontalDoubleTmuxSession  ($FirstFolder="*angular",$FirstCommand="npm start",$SecondFolder="*api",$SecondCommand="dotnet watch run") {
  $location = FuzzySearch-Location
	if($location) {
		Set-Location $location
		$currentDirectory = ($pwd.Path.Split("/") | Select -Last 1)
		tmux new-session `; `
			rename-session $currentDirectory `; `
			select-pane -t 0 `; `
			select-pane -T "NeoVim" `; `
			set -p '@pane_label' "NeoVim" `; `
			split-window -h -l 20% `; `
			select-pane -t 1 `; `
			select-pane -T "Terminal" `; `
			set -p '@pane_label' "Terminal" `; `
			send-keys "cd $FirstFolder" C-m `; `
			send-keys "$FirstCommand" C-m `; `
			select-pane -t 0 `; `
			select-pane -T "NeoVim" `; `
			set -p '@pane_label' "NeoVim" `; `
			send-keys "cd $FirstFolder" C-m `; `
			send-keys nvim C-m `; `
			new-window `; `
			select-pane -t 0 `; `
			select-pane -T "NeoVim" `; `
			set -p '@pane_label' "NeoVim" `; `
			split-window -h -l 20% `; `
			select-pane -t 1 `; `
			select-pane -T "Terminal" `; `
			set -p '@pane_label' "Terminal" `; `
			send-keys "cd $SecondFolder" C-m `; `
			send-keys "$SecondCommand" C-m `; `
			select-pane -t 0 `; `
			select-pane -T "NeoVim" `; `
			set -p '@pane_label' "NeoVim" `; `
			send-keys "cd $SecondFolder" C-m `; `
			send-keys nvim C-m `; `
			new-window `; `
			select-pane -t 0 `; `
			select-pane -T "Terminal" `; `
			set -p @pane_label "Terminal" `; `
			send-keys "htop" C-m `; `
			select-window -t 0
	}
	Write-Information "Cancelled by user"
}

function New-VerticalTmuxSession {
  <#
    .SYNOPSIS
      Opens tmux in this terminal: what is already open, else a project picked
      as prefix+/ picks one, with the home session beside it.

    .DESCRIPTION
      With a tmux server running here this is tmuxa (Get-TmuxSession): the
      group's current session, here or on a linked machine, else one of this
      machine's. A linked machine with nothing open any more sends it back
      here (Connect-Tmux.sh).

      With none, a project is asked for with prefix+/'s own picker,
      modules/tmux/scripts/New-CodeSession.sh -d: the ★ named sessions, the
      folders in the code folder and the linked machines'. It opens the session
      detached with the standard layout and prints where it is; a linked
      machine's folder is opened on that machine and attached to over ssh.

      The home session -- the one marked with H in the Git pane -- is opened
      too, so it is always there to come back to with prefix+h. It gets the
      home layout (Paperboy | Workhorse, Set-NeovimLayout.sh -H) in the
      directory Set-HomeSession.sh saved next to the mark, or
      $CODE_FOLDER/<name> for a mark saved before it kept one. Picking the
      home session's own project opens it just once, with the picker layout
      like any other.

      An ssh or Docker home session is opened over ssh instead, on the target
      and remote directory Set-HomeSession.sh saved in home-session-ssh, through
      New-SshSession.sh -t/-d/-n with its standard layout. That runs in this
      terminal before anything is attached, so a password, host key or the
      remote's key passphrase is asked for here first; leaving the prompt opens
      the picked project without it.

      Detached matters twice over: Connect-Tmux below only gets a terminal once
      the layouts are in place, and the explicit -x/-y give the windows the real
      terminal's size, so Set-NeovimLayout's percentage splits land where they
      will still be after attaching rather than being scaled up from tmux's
      default 80x24.

    .PARAMETER ExitOnCancel
      Exit the whole pwsh process with 130 -- fzf's own code for Esc/ctrl-c --
      when the project picker is aborted, instead of just returning.

      For callers that run this as the process's only job and need to tell "the
      user did not want tmux" apart from "the tmux session ended", which a plain
      return cannot express. modules/ghostty/scripts/Select-Shell.sh uses it to
      start plain pwsh instead. Off by default: exiting is the wrong answer
      when vtmux is typed at an interactive prompt, since it would take the
      session down with it.
  #>
  param([Switch]$ExitOnCancel)

  if(tmux ls 2> $null) {
    Get-TmuxSession
    return
  }

	$size = $Host.UI.RawUI.WindowSize
	# The session's name last, after the identity of the linked machine it is
	# on when it is not here. Nothing when the picker is left.
	$picked = @(& "$HOME/.modules/tmux/scripts/New-CodeSession.sh" -d -x $size.Width -y $size.Height | Where-Object { $_ })
	if(-not $picked) {
		Write-Information "Cancelled by user"
		if($ExitOnCancel) { exit 130 }
		return
	}
	$session = $picked[-1]
	$target = if($picked.Count -ge 2) { $picked[-2] } else { $null }

	$homeFile = "$(if($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { "$HOME/.cache" })/tmux/home-session"
	if([IO.File]::Exists($homeFile)) {
		$homeSession = [IO.File]::ReadAllText($homeFile).Trim()
		$homePath = if([IO.File]::Exists("$homeFile-path")) { [IO.File]::ReadAllText("$homeFile-path").Trim() } else { "$env:CODE_FOLDER/$homeSession" }
		$homeSsh = if([IO.File]::Exists("$homeFile-ssh")) { [IO.File]::ReadAllText("$homeFile-ssh").TrimEnd("`r", "`n").Split("`t") } else { @() }
		if($homeSession -and $homeSsh.Count -ge 3 -and $homeSsh[0] -and $homeSsh[1]) {
			$sshTarget, $sshDir, $sshName = $homeSsh[0..2]
			& "$HOME/.modules/tmux/scripts/New-SshSession.sh" -t $sshTarget -d $sshDir -n $sshName
			# The user@ in front of the name comes and goes with the other
			# users' sessions on that host, so the session may have opened
			# under another name than the mark's: the mark follows it.
			if(-not (tmux list-sessions -F '#{session_name}' 2> $null | Where-Object { $_ -eq $homeSession })) {
				$opened = tmux list-sessions -F "#{session_name}`t#{@ssh_target}`t#{@ssh_dir}" 2> $null |
					Where-Object { $f = $_.Split("`t"); $f[1] -eq $sshTarget -and $f[2] -eq $sshDir } |
					ForEach-Object { $_.Split("`t")[0] } | Select-Object -First 1
				# Set-HomeSession.sh toggles, but tmux holds the old name (the
				# config's -r put it back), so this sets the mark on the new one.
				if($opened) { & "$HOME/.modules/tmux/scripts/Set-HomeSession.sh" $opened }
			}
		} elseif($homeSession -and ($target -or $homeSession -ne $session) -and [IO.Directory]::Exists($homePath)) {
			tmux new-session -d -s $homeSession -c $homePath -x $size.Width -y $size.Height
			if($LASTEXITCODE -eq 0) {
				& "$HOME/.modules/tmux/scripts/Set-NeovimLayout.sh" -H -n "${homeSession}:"
			}
		}
	}
	Connect-Tmux $session -Target $target
}

function Start-Frontend() {
  <#
    .SYNOPSIS
      Runs the project's `npm run frontend` (ng serve + dotnet watch run) at a
      lowered scheduling priority.

    .DESCRIPTION
      A `dotnet watch` rebuild recompiles every source file in the API project
      and its domain project - there is no sub-project incrementality in Roslyn -
      and MSBuild sizes its parallelism to the core count, so a single rude edit
      saturates the machine while the Angular esbuild workers are also running.

      CPUWeight is a *relative share that only applies under contention*: on an
      idle machine the rebuild still gets every core at full speed, but as soon
      as something interactive wants CPU the editor and browser win. That is why
      this uses CPUWeight rather than CPUQuota, which would slow rebuilds down
      unconditionally.

      systemd-run --user needs the user's bus. A shell with no user session
      (an ssh command, a container) has none to reach, so it falls back to nice.
  #>
  if (!(Test-Path "package.json")) {
    Write-Warning "No package.json here. Run this from the Angular project folder."
    return
  }

  $userBus = $env:DBUS_SESSION_BUS_ADDRESS -or ($env:XDG_RUNTIME_DIR -and (Test-Path "$env:XDG_RUNTIME_DIR/bus"))
  if ($userBus -and (Get-Command systemd-run -ErrorAction SilentlyContinue)) {
    Write-Verbose "Starting frontend in a de-prioritised systemd scope"
    & systemd-run --user --scope --quiet -p CPUWeight=20 -p IOWeight=50 -- npm run frontend
  } elseif (Get-Command nice -ErrorAction SilentlyContinue) {
    # Same only-under-contention semantics, without the IO component.
    Write-Verbose "systemd-run unavailable. Falling back to nice"
    & nice -n 10 npm run frontend
  } else {
    Write-Verbose "Neither systemd-run nor nice available. Running unthrottled"
    & npm run frontend
  }
}

function Enable-Bash ($enable = $true) {
	if($enable) {
		$env:SKIP_PWSH=$true
	} else {
		$env:SKIP_PWSH=$null
	}
}

function Get-ChildItemsSize() {
	du -hs * | sort -hr | less
}

function Connect-Tmux ($Session, $Target) {
  <#
    .SYNOPSIS
      Attaches this terminal to a tmux session, through the script that can
      move it on to a linked machine's tmux and back.

    .DESCRIPTION
      `tmux attach-session` by another name, for vtmux and tmuxa: a session on
      a linked machine (prefix+N) is reached by this terminal leaving the local
      tmux and attaching to that one, which only the process around the tmux
      client can do. See modules/tmux/scripts/Connect-Tmux.sh.

      -Target attaches on that machine (its identity, user@hostname) rather
      than this one: for a session vtmux's picker opened on a linked machine.
  #>
	if($Target) {
		& "$HOME/.modules/tmux/scripts/Connect-Tmux.sh" -t $Target $Session
	} else {
		& "$HOME/.modules/tmux/scripts/Connect-Tmux.sh" $Session
	}
}

function Get-TmuxSession ($Session=$null) {
	if($Session) {
		Connect-Tmux $Session
	} elseif(& "$HOME/.modules/tmux/scripts/Sync-LinkGroup.sh" current 2> $null) {
		# No session asked for and this terminal's group has a current one, here
		# or on a linked machine: Connect-Tmux.sh goes to it by itself.
		Connect-Tmux
	} else {
		$tmuxListSessionsResult = tmux list-sessions;
		if($tmuxListSessionsResult -is [array]) {
			$tmuxSessions = (
					($tmuxListSessionsResult |
					 Select-Object @{l="Session";e={$_.Split(':')[0]}}
					).Session
					)
				$favoredSessions = "dev-environment"
				$availableFavoredSession = $null
				foreach($favoredSession in $favoredSessions) {
					if($tmuxSessions -eq $favoredSession) {
						$availableFavoredSession = $favoredSession
					}
				}
			if($availableFavoredSession){
				Connect-Tmux $availableFavoredSession
			} else {
				Connect-Tmux $tmuxSessions[0].Split(':')[0]
			}
		} else {
			if($tmuxListSessionsResult) {
				Connect-Tmux $tmuxListSessionsResult.Split(':')[0]
			}
		}
	}
}

function Get-OctalFilePermissions() {
  stat -c '%a | %n' *
}

function Copy-WindowsPrints([int]$Quantity = 1, [string]$OriginPath = $null, [string]$DestinationPath = $null) {
  if(!($OriginPath) -and $env:WINDOWS_PRINTS_PATH) {
    $OriginPath = $env:WINDOWS_PRINTS_PATH
  }
  if(!($DestinationPath) -and $env:PRINTS_RELATIVE_PATH) {
    $DestinationPath = $env:PRINTS_RELATIVE_PATH
  }
  if(!($OriginPath) -or !($DestinationPath)) {
    Write-Error "Both OriginPath and DestinationPath environment variables must be set."
  }
  $PrintsToBeCopied = Get-ChildItem $OriginPath |
    Sort-Object CreationTime -Descending |
    Select-Object -First $Quantity |
    ForEach-Object {
      Copy-Item -Path $_.FullName -Destination $DestinationPath -Force
      return "'$DestinationPath/$($_.Name)'"
    }
  return [string]::Join(", ", $PrintsToBeCopied)
}
New-Alias -Force htmux New-HorizontalTmuxSession
New-Alias -Force dhtmux New-HorizontalDoubleTmuxSession
New-Alias -Force vtmux New-VerticalTmuxSession
New-Alias -Force tmuxa Get-TmuxSession
New-Alias -Force duhs Get-ChildItemsSize
New-Alias -Force lso Get-OctalFilePermissions

Export-ModuleMember -Function * -Alias *
