@echo off
setlocal

rem Paths
set BIN_DIR=%USERPROFILE%\.bin
set KMONAD_EXE=%BIN_DIR%\kmonad.exe
set KBD_FILE=%USERPROFILE%\Git\dev-environment\WindowsHost\thomaz-k380.kbd

rem Run silently (no extra window)
start "" /B "%KMONAD_EXE%" "%KBD_FILE%"

endlocal

