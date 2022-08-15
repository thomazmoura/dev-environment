echo "\n->> Installing Azure CLI from pip" 
apt install python3 -y
pip install azure-cli

echo "\n->> Adding azure devops extensions"
az extension add --name azure-devops

