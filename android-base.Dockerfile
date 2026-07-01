ARG DockerBase
FROM $DockerBase

USER root

# JDK 17 (best compatibility with the Android Gradle Plugin 8.x; openjdk-17-jdk is available on Debian trixie)
RUN apt-get update && \
    apt-get install -y --no-install-recommends openjdk-17-jdk && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
ENV ANDROID_HOME="/home/developer/Android/Sdk"
ENV ANDROID_SDK_ROOT="/home/developer/Android/Sdk"
ENV PATH="${PATH}:${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator"

USER developer

# Android SDK (command-line tools, platform-tools, build-tools, platform, emulator, system image, AVD)
COPY --chown=developer:developer modules/powershell /home/developer/.modules/powershell
COPY --chown=developer:developer modules/android /home/developer/.modules/android
RUN pwsh -NoProfile -File /home/developer/.modules/android/Install-AndroidSdk.ps1

# Kotlin Language Server (fwcd) for NeoVim
RUN pwsh -NoProfile -File /home/developer/.modules/android/Install-KotlinLanguageServer.ps1
