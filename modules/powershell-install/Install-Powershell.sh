#!/bin/bash
set -eux

PWSH_VERSION="7.5.0"
PWSH_TARBALL="powershell-${PWSH_VERSION}-linux-x64.tar.gz"

echo ">>> Installing PowerShell ${PWSH_VERSION} from GitHub releases"

# Download PowerShell tarball
curl -sSL "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/${PWSH_TARBALL}" -o /tmp/powershell.tar.gz

# Create installation directory
mkdir -p /opt/microsoft/powershell/7

# Extract
tar -xzf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7

# Make executable
chmod +x /opt/microsoft/powershell/7/pwsh

# Create symlinks
ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh
ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/powershell

# Cleanup
rm /tmp/powershell.tar.gz

echo ">>> PowerShell installation complete"
