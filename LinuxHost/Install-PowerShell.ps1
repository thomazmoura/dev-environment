# Update the list of packages
sudo apt-get update
# Install pre-requisite packages.
sudo apt-get install -y wget apt-transport-https software-properties-common
# Download the Microsoft repository GPG keys
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb
# Update the list of packages after we added packages.microsoft.com
sudo apt-get update
# Install PowerShell
sudo apt-get install -y powershell
# Change default shel
chsh ${whoami} --shell $(which pwsh)

$PARENT_DIR="$(dirname $(dirname $(readlink -f $0)))"
$POWERSHELL_CONFIG="$PARENT_DIR/modules/powershell-config/linux-profile.ps1"
". $POWERSHELL_CONFIG" > $PROFILE.CurrentUserAllHosts
