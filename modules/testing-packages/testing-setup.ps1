Write-Output "`n->> Configuring the stable channel as default"
$FilePath = "/etc/apt/sources.list.d/99defaultrelease"
New-Item -Force $FilePath
Set-Content -Path $FilePath -Value 'APT::Default-Release "stable";'

Write-Output "`n->> Moving the lists"
Move-Item "$PSScriptRoot/stable.list" /etc/apt/sources.list.d/
Move-Item "$PSScriptRoot/testing.list" /etc/apt/sources.list.d/

Write-Output "`n->> Updating the packages cache"
& apt update
