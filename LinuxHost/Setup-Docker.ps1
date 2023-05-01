param(
  [String]$Command='if( tmux ls 2> $null ) { tmuxa } else { vtmux }',
  [String]$ContainerName='dev-env',
  [String]$ContainerTag=':latest'
)

if( !(service docker status) ){
  Write-Information "`n->> Starting docker"
	sudo service docker start
}

Write-Information "`n->> Killing and removing the $ContainerName container if it's running"
sudo docker kill $ContainerName *> /dev/null
sudo docker rm $ContainerName *> /dev/null

Write-Information "`n->> Updating the container"
sudo docker pull thomazmoura/dev-environment$ContainerTag

Write-Information "`n->> Creating the code volume (if it does not exist)"
sudo docker volume create code *> /dev/null

Write-Information "`n->> Creating the storage volume (if it does not exist)"
sudo docker volume create storage *> /dev/null

Write-Information "`n->> Creating the network (if it does not exist)"
sudo docker network create dev-environment-network *> /dev/null

Write-Information "`n->> Fixing the volume folders permissions"
sudo docker container run --user root:root -v "$HOME/.shared:/home/developer/.shared" --env-file "$HOME/.docker-variables" -it --rm --name dev-env-fix thomazmoura/dev-environment$ContainerTag /bin/bash -c "chown -R developer:developer /home/developer/.shared"
sudo docker container run --user root:root -v storage:/home/developer/.storage --env-file "$HOME/.docker-variables" -it --rm --name dev-env-fix thomazmoura/dev-environment$ContainerTag /bin/bash -c "chown -R developer:developer /home/developer/.storage"
sudo docker container run --user root:root --env-file "$HOME/.docker-variables" -it --rm --name dev-env-fix thomazmoura/dev-environment$ContainerTag /bin/bash -c "chown -R developer:developer /home/developer/.hosts"

Write-Information "`n->> Creating the $ContainerName container"
sudo docker container run -v code:/home/developer/code -v storage:/home/developer/.storage -v "$HOME/.shared:/home/developer/.shared" -p 4200:4200 -p 5000:5000 -p 5001:5001 -p 5500:5500 -p 5501:5501 --env-file "$HOME/.docker-variables" -it -d --network dev-environment-network --name $ContainerName thomazmoura/dev-environment$ContainerTag

