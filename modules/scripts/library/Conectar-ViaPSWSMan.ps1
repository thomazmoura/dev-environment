Write-Host "Informe o servidor"
$servidor = Read-Host

Write-Host "->> Importando o módulo PSWSMan..."
Import-Module PSWSMan

Write-Host "->> Habilitando o  módulo PSWSMan..."
Enable-PSWSMan -Force

Write-Host "->> Conectando ao servidor $servidor..."
Enter-PSSession -ComputerName $servidor -Authentication Kerberos
