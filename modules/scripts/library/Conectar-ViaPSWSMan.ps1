# Abre uma sessão remota (WSMan/Kerberos) num servidor Windows via PSWSMan.
#
# Uso: Conectar-ViaPSWSMan.ps1 [-Servidor <host>] [-Autenticacao <Kerberos|Negotiate|...>]
# Sem -Servidor, pergunta (é assim que o picker do prefix,s o chama).
#
# O Enable-PSWSMan (PSWSMan 3.0.0) usa um MonoMod que não suporta .NET 11, o runtime
# do pwsh 7.7+. Por isso o host usa o pacote powershell-lts (7.6, .NET 10) como pwsh
# (LinuxDevEnv/host-setup.sh); os dois pacotes não coexistem, ambos têm /usr/bin/pwsh.
param(
  [string] $Servidor,
  [string] $Autenticacao = 'Kerberos'
)

if (-not $Servidor) {
  Write-Host "Informe o servidor"
  $Servidor = Read-Host
}
if (-not $Servidor) {
  Write-Host "->> Nenhum servidor informado." -ForegroundColor Red
  exit 1
}

if ([Environment]::Version.Major -ge 11) {
  Write-Host "->> O PSWSMan não roda no .NET $([Environment]::Version) (pwsh $($PSVersionTable.PSVersion))." -ForegroundColor Red
  Write-Host "    Troque para o pwsh LTS: sudo apt remove -y powershell && sudo apt install -y powershell-lts" -ForegroundColor Red
  exit 1
}

Write-Host "->> Importando o módulo PSWSMan..."
Import-Module PSWSMan

Write-Host "->> Habilitando o módulo PSWSMan..."
Enable-PSWSMan -Force

Write-Host "->> Conectando ao servidor $Servidor..."
Enter-PSSession -ComputerName $Servidor -Authentication $Autenticacao
