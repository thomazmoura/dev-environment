. "$HOME/.modules/powershell/Check-Failure.ps1"

$KotlinLspFolder = "$HOME/.language-servers/kotlin"

if( Test-Path "$KotlinLspFolder/server/bin/kotlin-language-server" ) {
  Write-Output "`n->> Kotlin Language Server already installed. Skipping."
  return
}

Write-Output "`n->> Installing fwcd kotlin-language-server into $KotlinLspFolder"
New-Item -Force -Type Directory -Path $KotlinLspFolder | Out-Null
Push-Location $KotlinLspFolder
# The 'latest' alias always resolves to the most recent release's server.zip asset
Invoke-WebRequest "https://github.com/fwcd/kotlin-language-server/releases/latest/download/server.zip" -OutFile "server.zip"
& unzip -q -o "server.zip" -d $KotlinLspFolder
Remove-Item -Force "server.zip"
Pop-Location

Throw-ExceptionOnNativeFailure
