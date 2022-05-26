$InformationPreference = "Continue";

. $HOME/.modules/powershell/pwsh-modules.ps1

# Vi style cursor
$stopwatch = [system.diagnostics.stopwatch]::StartNew()
if ($PSVersionTable.PSVersion.Major -ge 6) {
  Write-Host -NoNewLine "`e[5 q"
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

# Enable prediction
$stopwatch = [system.diagnostics.stopwatch]::StartNew()
try {
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
if ( Test-Path "~/git/CI-CD"  ) {
  Write-Verbose "`n->> CI-CD folder found, adding Utilitarios to PATH"
  $env:PATH = "~/git/CI-CD/Utilitarios:~/git/CI-CD/QuickStarts/Scripts:${env:PATH}"
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
  return (fd . $dir --type f --follow | fzf)
}
function FuzzySearch-Location($dir = "$env:CODE_FOLDER") {
  return (fd . $dir --type d --follow | fzf)
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
  $selectedItem = (fd sln $dir --type f --follow | fzf)
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

function Start-DotnetWatch([String]$Profile, [Switch]$SkipAutoUrls) {
  if($SkipAutoUrls -or !(Test-Path "./Properties/launchSettings.json") ) {
    Write-Verbose "Skipping auto exposing URLs"
    & dotnet watch run
    return;
  }

  if(!($Profile)) {
    $Profile = (Get-Item $PWD).Name
    Write-Verbose "No Profile informed. Using $Profile as Profile"
  }
  $LaunchSettings = Get-Content "./Properties/launchSettings.json" | ConvertFrom-Json
  $ApplicationUrls = $LaunchSettings.profiles.$Profile.applicationUrl

  if($ApplicationUrls) {
    $ExposedUrls = $ApplicationUrls.Replace("localhost", "0.0.0.0")
    Write-Verbose "Running with the following URLs (Based on ./Properties/launchSettings.json and exposed to accessible from outside the container): $ExposedUrls"
    & dotnet watch run -- --urls="$ExposedUrls"
  } else {
    Write-Verbose "No applicationUrl detected on profile. Skipping auto exposing URLs"
    & dotnet watch run
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

function ConvertTo-Base64([string]$Text) {
  $Bytes = [System.Text.Encoding]::Unicode.GetBytes($Text)
  $EncodedText = [Convert]::ToBase64String($Bytes)
  $EncodedText
}

function ConvertFrom-Base64([string]$Text) {
  $Bytes = [System.Convert]::FromBase64String($Text);
  $DecodedText = ([System.Text.Encoding]::Unicode.GetString($Bytes))
  $DecodedText
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

function Add-SshKey($SshKeyFolder = "$HOME/.ssh") {
  $sshKey = "$SshKeyFolder/id_rsa"
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

function Start-SqlServerDockerContainer($Version = "2017-latest", [switch]$Interactive) {
  if ($Interactive) {
    docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=L0c4lD3v!" -p 1433:1433 -it --rm -v localdb:/var/opt/mssql/data/ --name mssql mcr.microsoft.com/mssql/server:$version
  }
  else {
    docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=L0c4lD3v!" -p 1433:1433 -d --rm -v localdb:/var/opt/mssql/data/ --name mssql mcr.microsoft.com/mssql/server:$version
  }
}

function Set-LocalContextDatabase($DatabaseName = "contexto", $ContextName = "Contexto", $DataSourceName = "mssql", $UserId = "sa", $Password = "L0c4lD3v!") {
  if (!$DatabaseName) {
    $env:ConnectionStrings__Contexto = $null
  }
  else {
    [Environment]::SetEnvironmentVariable("ConnectionStrings__$ContextName", "Data Source=$DataSourceName;Initial Catalog=$DatabaseName;Persist Security Info=True;User Id=$UserId;Password=$Password")
  }
}

function Exit-Session() {
  exit
}

function Set-AutoNodeVersion() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if(!(Get-Command nvs -ErrorAction SilentlyContinue) -or !(Get-Command fd -ErrorAction SilentlyContinue)) {
    Write-Verbose "fd or nvs not found. Skipping"
  }

  $nodeVersionFile = (fd --hidden .node-version)
  if(!($nodeVersionFile)) {
    Write-Verbose ".node-version not found"
    return;
  }
  if($nodeVersionFile -is [array]) {
    Write-Verbose "More than a single .node-version found"
    return;
  }

  nvs use (Get-Content $nodeVersionFile)
  $stopwatch.Stop(); Write-Verbose "`n-->> Ativação do NVS demorou: $($stopwatch.ElapsedMilliseconds)"
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
New-Alias -Force gitdfc GitDiff-StagedChanges
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

New-Alias -Force ddwr Start-DockerDotnetWatchRun

New-Alias -Force poshgit Import-PoshGit
New-Alias -Force psgit Import-PoshGit
New-Alias -Force psomp Import-OhMyPoshOnLinux
New-Alias -Force omp Import-OhMyPoshOnLinux
New-Alias -Force psfzf Import-PsFzf
New-Alias -Force psaws Import-PsAWS
New-Alias -Force psnvm Import-PsNvm
New-Alias -Force psdocker Import-DockerCompletion

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
