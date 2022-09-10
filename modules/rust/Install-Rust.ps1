. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Information "`n->> Installing Rust (with RustUp)"
& curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

Write-Information "`n->> Updating path to include cargo"

$UpdatedPath = "$env:PATH`:$HOME/.cargo/bin"
[System.Environment]::SetEnvironmentVariable("PATH", $UpdatedPath, "Process");

Write-Information "`n->> Installing Cargo modules"
& cargo install cargo-watch

& git clone https://github.com/rust-lang/rust-analyzer.git /home/developer/code/rust-analyzer && Push-Location /home/developer/code/rust-analyzer
& cargo xtask install --server && Pop-Location && rm -rf /home/developer/code/rust-analyzer

Throw-ExceptionOnNativeFailure

