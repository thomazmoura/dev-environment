$Dotnet6FolderAspNet = Get-ChildItem "/usr/lib/dotnet/shared/Microsoft.AspNetCore.App/6*"
$Dotnet6FolderNet = Get-ChildItem "/usr/lib/dotnet/shared/Microsoft.NETCore.App/6*"

$Dotnet6FolderSymbolicLinkAspNet = Get-ChildItem "/usr/share/dotnet/shared/Microsoft.AspNetCore.App/6*"
$Dotnet6FolderSymbolicLinkNet = Get-ChildItem "/usr/share/dotnet/shared/Microsoft.NETCore.App/6.*"

if ($Dotnet6FolderSymbolicLinkAspNet) {
  Write-Information "Removendo $Dotnet6FolderSymbolicLinkAspNet para que seja recriado"
  sudo pwsh -C "Remove-Item $Dotnet6FolderSymbolicLinkAspNet"
}

if ($Dotnet6FolderSymbolicLinkNet) {
  Write-Information "Removendo $Dotnet6FolderSymbolicLinkNet para que seja recriado"
  sudo pwsh -C "Remove-Item $Dotnet6FolderSymbolicLinkNet"
}

$DotnetAsp6FolderVersion = $Dotnet6FolderAspNet.Name
$DotnetAsp6FolderSymbolicLinkAspNetPath = "/usr/share/dotnet/shared/Microsoft.AspNetCore.App/$DotnetAsp6FolderVersion"
Write-Information "Criando o link simbólico em $DotnetAsp6FolderSymbolicLinkAspNetPath para acessar $Dotnet6FolderAspNet"
sudo pwsh -C "New-Item -ItemType SymbolicLink -Path $DotnetAsp6FolderSymbolicLinkAspNetPath -Target $Dotnet6FolderAspNet"

$Dotnet6FolderVersion = $Dotnet6FolderNet.Name
$Dotnet6FolderSymbolicLinkNetPath = "/usr/share/dotnet/shared/Microsoft.NETCore.App/$Dotnet6FolderVersion"
Write-Information "Criando o link simbólico em $Dotnet6FolderSymbolicLinkNetPath para acessar $Dotnet6FolderNet"
sudo pwsh -C "New-Item -ItemType SymbolicLink -Path $Dotnet6FolderSymbolicLinkNetPath -Target $Dotnet6FolderNet"

