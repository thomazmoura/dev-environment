echo "->> Installing Azure CLI from pip" 
pip install azure-cli

echo "->> Adding azure devops extensions"
/usr/local/bin/az extension add --name azure-devops

