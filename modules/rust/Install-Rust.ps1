. "$HOME/.modules/powershell/Check-Failure.ps1"

Write-Information "`n->> Installing Rust (with RustUp)"
& curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

Write-Information "`n->> Installing Cargo modules"
& cargo install cargo-watch

Throw-ExceptionOnNativeFailure

