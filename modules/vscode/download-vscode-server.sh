#!/bin/sh
# Script gotten from https://gist.github.com/b01/0a16b6645ab7921b0910603dfb85e4fb
#   and simplified with suggestions from https://stackoverflow.com/a/57601121/3016982

set -e

ARCH="x64"
U_NAME=$(uname -m)

if [ "${U_NAME}" = "aarch64" ]; then
    ARCH="arm64"
fi

archive="vscode-server-linux-${ARCH}.tar.gz"
owner='microsoft'
repo='vscode'
commit_sha='latest'

if [ -n "${commit_sha}" ]; then
    echo "will attempt to download VS Code Server version = '${commit_sha}'"

    # Download VS Code Server tarball to tmp directory.
    curl -L "https://update.code.visualstudio.com/${commit_sha}/server-linux-${ARCH}/stable" -o "/tmp/${archive}"

    # Make the parent directory where the server should live.
    # NOTE: Ensure VS Code will have read/write access; namely the user running VScode or container user.
    mkdir -vp ~/.vscode-server/"${commit_sha}"

    # Extract the tarball to the right location.
    tar --no-same-owner -xzv --strip-components=1 -C ~/.vscode-server/"${commit_sha}" -f "/tmp/${archive}"

    # Delete the tar file
    rm -rf "/tmp/${archive}"
else
    echo "could not pre install vscode server"
fi
