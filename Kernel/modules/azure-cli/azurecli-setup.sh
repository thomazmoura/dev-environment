echo "Updating apt-get and installing dependencies" 
apt-get update & apt-get install ca-certificates curl apt-transport-https lsb-release gnupg

echo "Downloading Microsoft signing key"
curl -sL https://packages.microsoft.com/keys/microsoft.asc |
    gpg --dearmor |
    tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null

echo "Adding the Azure CLI software repository"
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" |
    tee /etc/apt/sources.list.d/azure-cli.list

echo "Updating apt-get and installing azure-cli"
apt-get update
apt-get install azure-cli

echo "Adding azure devops extensions"
az extension add --name azure-devops

