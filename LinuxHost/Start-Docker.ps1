param(
  [String]$Command='if( tmux ls 2> $null ) { tmuxa } else { vtmux }',
  [String]$ContainerName='dev-env'
)

if( !(service docker status) ){
  Write-Information "`n->> Starting docker"
	sudo service docker start
}

Write-Information "`n->> Starting dev-env container"
sudo docker start $ContainerName

Write-Information "`n->> Attaching to dev-env container"
sudo docker container exec -it $ContainerName pwsh -c $Command

