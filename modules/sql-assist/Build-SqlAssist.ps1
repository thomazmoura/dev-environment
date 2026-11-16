# Builds the sql-assist language servers (see README.md) into ~/.language-servers:
# sqlserver-assist from sqlserver/ and postgres-assist from postgres/, both with common/.
# Called by modules/neovim-lsp/Setup-NeoVimLSP.ps1; run it again after changing their code,
# then :lsp restart in NeoVim.
#
# The build's intermediate files go to ~/.cache/sql-assist, so the repo gets no bin/ or obj/.
# It is built where it runs (the image, the host), so only this platform's native libraries
# are kept. Each output is emptied first, so a removed dependency leaves no DLL behind.
. "$HOME/.modules/powershell/Check-Failure.ps1"

$Artifacts = Join-Path ($env:XDG_CACHE_HOME ?? "$HOME/.cache") 'sql-assist/build'
$Servers = [ordered]@{
  'sqlserver-assist' = "$PSScriptRoot/sqlserver/SqlServerAssist.csproj"
  'postgres-assist'  = "$PSScriptRoot/postgres/PostgresAssist.csproj"
}

foreach ($Server in $Servers.GetEnumerator()) {
  $Output = "$HOME/.language-servers/$($Server.Key)"
  Remove-Item -Recurse -Force -Path $Output -ErrorAction SilentlyContinue
  & dotnet publish $Server.Value --configuration Release --output $Output `
    --use-current-runtime --self-contained false `
    --artifacts-path $Artifacts --nologo
  Throw-ExceptionOnNativeFailure
}
