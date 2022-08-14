# Based on https://stackoverflow.com/a/44810914/3016982
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['*:ErrorAction']='Stop'

function ThrowOnNativeFailure {
    if (-not $?)
    {
        throw 'Native Failure'
    }
}
