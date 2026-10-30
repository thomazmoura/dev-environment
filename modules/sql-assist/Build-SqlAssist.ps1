# Builds the sql-assist language servers (see README.md) into ~/.language-servers: today
# sqlserver-assist, from sqlserver/. Called by modules/neovim-lsp/Setup-NeoVimLSP.ps1; run it
# again after changing their code, then :lsp restart in NeoVim.
#
# The build's intermediate files go to ~/.cache/sql-assist, so the repo gets no bin/ or obj/.
# It is built where it runs (the image, the host), so only this platform's native libraries
# are kept. The output is emptied first, so a removed dependency leaves no DLL behind.
. "$HOME/.modules/powershell/Check-Failure.ps1"

$Output = "$HOME/.language-servers/sqlserver-assist"
$Artifacts = Join-Path ($env:XDG_CACHE_HOME ?? "$HOME/.cache") 'sql-assist/build'

Remove-Item -Recurse -Force -Path $Output -ErrorAction SilentlyContinue
& dotnet publish "$PSScriptRoot/sqlserver/SqlServerAssist.csproj" --configuration Release --output $Output `
  --use-current-runtime --self-contained false `
  --artifacts-path $Artifacts --nologo
Throw-ExceptionOnNativeFailure
