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

function Add-SshKey($SshKeyFolder = "$HOME/.ssh", $SshKeyFile = $null) {
  # The key to add: the one asked for, else the one $env:SSH_KEY_FILE names,
  # else the first key in the folder that has a .pub beside it.
  if (!$SshKeyFile) { $SshKeyFile = $env:SSH_KEY_FILE }
  if (!$SshKeyFile) {
    $pub = Get-ChildItem -Path $SshKeyFolder -Filter "*.pub" -File -ErrorAction SilentlyContinue |
      Sort-Object Name | Select-Object -First 1
    if ($pub) { $SshKeyFile = $pub.BaseName }
  }
  if (!$SshKeyFile) {
    Write-Information "`n->> No SSH key found in $SshKeyFolder"
    return
  }
  $sshKey = "$SshKeyFolder/$SshKeyFile"
  # An agent handed down with both variables -- by the tmux server locally, or
  # by an ssh session's pane from the host's shared agent
  # (modules/tmux/scripts/ssh-helpers.sh) -- is the one to use while it still
  # answers. ssh-add -L exits 2 only when there is no agent to talk to, and its
  # output is kept for Test-SshKeyInAgent below, so every shell start pays for
  # one ssh-add launch instead of two.
  $agentAlive = $env:SSH_AUTH_SOCK -and $env:SSH_AGENT_PID
  $agentKeys = $null
  $agentExitCode = 2
  if ($agentAlive) {
    $agentKeys = ssh-add -L 2> $null
    $agentExitCode = $LASTEXITCODE
    $agentAlive = $agentExitCode -ne 2
  }
  if ( !$agentAlive -and (Test-Path $sshKey) ) {
    Write-Verbose "`n->> Adding SSH key"
    $sshAgent = ssh-agent;
    $env:SSH_AUTH_SOCK = $sshAgent[0].Split("=").Split(";")[1]
    $env:SSH_AGENT_PID = $sshAgent[1].Split("=").Split(";")[1]
    ssh-add $sshKey
  }
  elseif ( (Test-Path $sshKey) -and !(Test-SshKeyInAgent $sshKey -AgentKeys $agentKeys -AgentExitCode $agentExitCode) ) {
    # The agent is running but no longer has the key: it outlived the key's
    # lifetime, or the key was removed. Added back into that same agent, so
    # this pane asks and the ones after it don't.
    Write-Verbose "`n->> Adding SSH key to the running agent"
    ssh-add $sshKey
  }
  else {
    Write-Information "`n->> SSH Agent already added"
  }
  Write-Information "`n->> Agent PID: $env:SSH_AGENT_PID"
}

# Whether the agent in SSH_AUTH_SOCK holds this private key, judged by its
# public half: the first two fields of the .pub (type and key) against each
# line of ssh-add -L. Without a .pub there is nothing to compare, and any key
# in the agent is taken to be this one -- what Add-SshKey assumed before it
# compared at all. -AgentKeys/-AgentExitCode take an ssh-add -L the caller
# already ran; without them it asks the agent itself.
function Test-SshKeyInAgent($SshKey, $AgentKeys, $AgentExitCode) {
  if (!$PSBoundParameters.ContainsKey('AgentExitCode')) {
    $AgentKeys = ssh-add -L 2> $null
    $AgentExitCode = $LASTEXITCODE
  }
  $pub = "$SshKey.pub"
  if (!(Test-Path $pub)) {
    return $AgentExitCode -eq 0
  }
  $id = ((Get-Content $pub -TotalCount 1) -split ' ')[0..1] -join ' '
  $loaded = $AgentKeys | Where-Object { (($_ -split ' ')[0..1] -join ' ') -eq $id }
  return [bool]$loaded
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
# NeoVim (LSP servers and Copilot) and the Copilot CLI, in
# modules/tmux/scripts/tmux-helpers.sh, modules/tmux/common.conf and
# modules/herdr/scripts/workspace-actions.sh.
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
      Opens the first tmux session of the day on a project picked with fzf.

    .DESCRIPTION
      The layout itself is not built here: the session is created detached and
      handed to modules/tmux/scripts/Set-NeovimLayout.sh, which is the same
      script behind prefix+v and behind prefix+C-n's New-CodeSession.sh. That
      is deliberate -- this function used to spell the panes out inline and
      drifted from the bindings every time the layout changed.

      Detached matters twice over: `tmux attach-session` below only gets a
      terminal once the layout is in place, and the explicit -x/-y give the
      window the real terminal's size, so Set-NeovimLayout's percentage splits
      land where they will still be after attaching rather than being scaled up
      from tmux's default 80x24.

    .PARAMETER ExitOnCancel
      Exit the whole pwsh process with 130 -- fzf's own code for Esc/ctrl-c --
      when the project picker is aborted, instead of just returning.

      For callers that run this as the process's only job and need to tell "the
      user did not want tmux" apart from "the tmux session ended", which a plain
      return cannot express. modules/ghostty/scripts/Select-Shell.sh uses it to
      fall back to its shell picker. Off by default: exiting is the wrong answer
      when vtmux is typed at an interactive prompt, since it would take the
      session down with it.
  #>
  param([Switch]$ExitOnCancel)

  if(tmux ls 2> $null) {
    Get-TmuxSession
    return
  }

  $location = FuzzySearch-Location
	if($location) {
		Set-Location $location
		# tmux session names cannot contain dots -- they separate session:window.pane.
		$currentDirectory = ($pwd.Path.Split("/") | Select-Object -Last 1).Replace(".", "_")
		$size = $Host.UI.RawUI.WindowSize
		tmux new-session -d -s $currentDirectory -c $location -x $size.Width -y $size.Height
		& "$HOME/.modules/tmux/scripts/Set-NeovimLayout.sh" -n "${currentDirectory}:"
		tmux attach-session -t $currentDirectory
		return
	}
	Write-Information "Cancelled by user"
	if($ExitOnCancel) { exit 130 }
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
  #>
  if (!(Test-Path "package.json")) {
    Write-Warning "No package.json here. Run this from the Angular project folder."
    return
  }

  if (Get-Command systemd-run -ErrorAction SilentlyContinue) {
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

function Get-TmuxSession ($Session=$null) {
	if($Session) {
		tmux attach-session -t $Session
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
				tmux attach-session -t $availableFavoredSession
			} else {
				tmux attach-session -t $tmuxSessions[0].Split(':')[0]
			}
		} else {
			if($tmuxListSessionsResult) {
				tmux attach-session -t $tmuxListSessionsResult.Split(':')[0]
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
