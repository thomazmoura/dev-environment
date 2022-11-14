echo "\n->> Killing and removing the dev-env container if it's running"
sudo /usr/bin/docker kill dev-env &> /dev/null
sudo /usr/bin/docker rm dev-env &> /dev/null

echo "\n->> Updating the container"
sudo /usr/bin/docker pull thomazmoura/dev-environment:feature_36-native-omnisharp-lsp

echo "\n->> Creating the code volume (if it does not exist)"
sudo /usr/bin/docker volume create code &> /dev/null

echo "\n->> Creating the storage volume (if it does not exist)"
sudo /usr/bin/docker volume create storage &> /dev/null

echo "\n->> Creating the network (if it does not exist)"
sudo /usr/bin/docker network create dev-environment-network &> /dev/null

echo "\n->> Creating the dev-env container"
sudo /usr/bin/docker container run -v code:/home/developer/code -v storage:/home/developer/.storage -v "$HOME/.shared:/home/developer/.shared" -p 4200:4200 -p 5000:5000 -p 5001:5001 -p 5500:5500 -p 5501:5501 --env-file "$HOME/.docker-variables" -it -d --network dev-environment-network --name dev-env thomazmoura/dev-environment:feature_36-native-omnisharp-lsp

