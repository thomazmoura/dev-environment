. "$HOME/.modules/powershell/Check-Failure.ps1"

# Versions / configuration (bump these to upgrade the toolchain)
$CommandLineToolsVersion = "11076708"
$AndroidApiLevel = "35"
$BuildToolsVersion = "35.0.0"
$SystemImage = "system-images;android-$AndroidApiLevel;google_apis;x86_64"
$AvdName = "pixel_api35"
$AvdDevice = "pixel_7"

$AndroidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$HOME/Android/Sdk" }
$SdkManager = "$AndroidHome/cmdline-tools/latest/bin/sdkmanager"
$AvdManager = "$AndroidHome/cmdline-tools/latest/bin/avdmanager"

if( Test-Path "$AndroidHome/platform-tools" ) {
  Write-Output "`n->> Android SDK already installed at $AndroidHome. Skipping SDK install."
} else {
  Write-Output "`n->> Installing Android command-line tools into $AndroidHome"
  New-Item -Force -Type Directory -Path "$AndroidHome/cmdline-tools" | Out-Null
  New-Item -Force -Type Directory -Path "$HOME/Downloads" | Out-Null
  $ZipPath = "$HOME/Downloads/commandlinetools.zip"
  Invoke-WebRequest "https://dl.google.com/android/repository/commandlinetools-linux-${CommandLineToolsVersion}_latest.zip" -OutFile $ZipPath
  # The zip extracts to a folder named 'cmdline-tools'; sdkmanager expects it under 'cmdline-tools/latest'
  & unzip -q -o $ZipPath -d "$AndroidHome/cmdline-tools"
  Remove-Item -Recurse -Force "$AndroidHome/cmdline-tools/latest" -ErrorAction SilentlyContinue
  Move-Item "$AndroidHome/cmdline-tools/cmdline-tools" "$AndroidHome/cmdline-tools/latest"
  Remove-Item -Force $ZipPath

  Write-Output "`n->> Accepting Android SDK licenses"
  & bash -c "yes | '$SdkManager' --sdk_root='$AndroidHome' --licenses" | Out-Null

  Write-Output "`n->> Installing SDK packages (platform-tools, build-tools, platform, emulator, system image)"
  & bash -c "yes | '$SdkManager' --sdk_root='$AndroidHome' 'platform-tools' 'emulator' 'cmdline-tools;latest' 'platforms;android-$AndroidApiLevel' 'build-tools;$BuildToolsVersion' '$SystemImage'"
}

Write-Output "`n->> Ensuring AVD '$AvdName' exists"
$ExistingAvds = & $AvdManager list avd 2>$null
if( $ExistingAvds -match $AvdName ) {
  Write-Output "`n->> AVD '$AvdName' already exists. Skipping."
} else {
  & bash -c "echo no | '$AvdManager' create avd -n '$AvdName' -k '$SystemImage' -d '$AvdDevice'"
}

Throw-ExceptionOnNativeFailure
