. "$HOME/.modules/powershell/Check-Failure.ps1"

& curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
& git clone https://github.com/rust-lang/rust-analyzer.git && Push-Location rust-analyzer
& cargo xtask install --server
Pop-Location && Remove-Item -Recurse -Force rust-analyzer

Throw-ExceptionOnNativeFailure

