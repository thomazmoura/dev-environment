function Import-PsFzf() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if ( !(Get-Module PsFzf) ) {
    Write-Information "`n->> PSFzf not found. Installing"
    Install-Module -Force -AcceptLicense PSFzf 
  }
  Write-Verbose "`n->> Importing PSFzf"
  Import-Module PSFzf -ArgumentList 'Ctrl+t', 'Ctrl+r' -ErrorAction Stop
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do PsFzf demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-PsAWS([string]$region = "sa-east-1") {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if ( !(Get-Module AWSPowerShell.NetCore) ) {
    Write-Information "`n->> AWSPowerShell.NetCore not found. Installing"
    Install-Module -Force -AcceptLicense -Name AWSPowerShell.NetCore
  }
  Write-Verbose "`n->> Importing AWS CLI"
  Import-Module -Name AWSPowerShell.NetCore -ErrorAction Stop
  Set-DefaultAWSRegion -Region $region -Scope Global
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do PsAWS demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-DockerCompletion() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if(Get-Command docker -ErrorAction SilentlyContinue) {
    if ( !(Get-Module DockerCompletion) ) {
      Write-Information "`n->> DockerCompletion not found. Installing"
      Install-Module -Force -AcceptLicense DockerCompletion -ErrorAction Stop
    }
    Write-Verbose "`n->> Importing DockerCompletion"
    Import-Module DockerCompletion -ErrorAction Stop
  } else {
      Write-Verbose "`n->> Docker not found. Skipping DockerCompletion"
  }
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do autocomplete do docker demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-PoshGit() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if ( !(Get-Module posh-git) ) {
    Write-Information "`n->> Posh-git not found. Installing"
    Install-Module -Force -AcceptLicense posh-git -ErrorAction Stop
  }
  Write-Verbose "`n->> Importing posh-git"
  Import-Module posh-git -ErrorAction Stop
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do Posh-git demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-OhMyPoshOnLinux() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  Write-Verbose "`n->> Activating oh-my-posh"
  if( !(Get-Command oh-my-posh -ErrorAction SilentlyContinue) ) {
    if(!(Test-Path "$HOME/.local/bin") ) {
      New-Item -Force -ItemType Directory -Name "$HOME/.local/bin";
    }
    "wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O $HOME/.local/bin/oh-my-posh" | Invoke-Expression
    "chmod +x $HOME/.local/bin/oh-my-posh" | Invoke-Expression
  } else {
    Write-Verbose "OhMyPosh instalado corretamente"
  }
  & $HOME/.local/bin/oh-my-posh init pwsh --config $HOME/.config/powershell/linux.omp.json | Invoke-Expression
  Write-Information "Carregado o arquivo $HOME/.config/powershell/linux.omp.json"
  $stopwatch.Stop(); Write-Information "`n-->> Importação do Oh-My-Posh demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Update-PSReadline() {
  Write-Verbose "`n->> Updating PSReadLine"
  Install-Module -Name PSReadLine -Force
}

