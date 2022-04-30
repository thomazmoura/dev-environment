function Import-PsFzf() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  Write-Verbose "`n->> Importing PSFzf"
  Import-Module PSFzf -ArgumentList 'Ctrl+t', 'Ctrl+r'
  if ( !($?) ) {
    Write-Information "`n->> PSFzf not found. Installing"
    Install-Module -Force -AcceptLicense PSFzf 
    Import-Module PSFzf -ArgumentList 'Ctrl+t', 'Ctrl+r'
  }
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do PsFzf demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-PsAWS([string]$region = "sa-east-1") {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  Write-Verbose "`n->> Importing AWS CLI"
  Import-Module -Name AWSPowerShell.NetCore
  if ( !($?) ) {
    Write-Information "`n->> AWSPowerShell.NetCore not found. Installing"
    Install-Module -Force -AcceptLicense -Name AWSPowerShell.NetCore
    Import-Module -Name AWSPowerShell.NetCore
  }
  Set-DefaultAWSRegion -Region $region -Scope Global
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do PsAWS demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-DockerCompletion() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  if(Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Verbose "`n->> Importing DockerCompletion"
    Import-Module DockerCompletion
    if ( !($?) ) {
      Write-Information "`n->> DockerCompletion not found. Installing"
      Install-Module -Force -AcceptLicense DockerCompletion
      Import-Module DockerCompletion
    }
  } else {
      Write-Verbose "`n->> Docker not found. Skipping DockerCompletion"
  }
  $stopwatch.Stop(); Write-Verbose "`n-->> Importação do autocomplete do docker demorou: $($stopwatch.ElapsedMilliseconds)"
}

function Import-PoshGit() {
  $stopwatch =  [system.diagnostics.stopwatch]::StartNew()
  Write-Verbose "`n->> Importing posh-git"
  Import-Module posh-git
  if ( !($?) ) {
    Write-Information "`n->> Posh-git not found. Installing"
    Install-Module -Force -AcceptLicense posh-git -Scope CurrentUser
  }
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

