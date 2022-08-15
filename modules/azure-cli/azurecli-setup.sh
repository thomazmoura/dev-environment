echo "->> Installing Azure CLI from pip" 
apt install python3 -y
pip install azure-cli

echo "->> Adding azure devops extensions"
az extension add --name azure-devops

