param(
  [String]$Command='if( tmux ls 2> $null ) { tmuxa } else { vtmux }',
  [String]$ContainerName='dev-env'
)

if( !(/usr/sbin/service docker status) ){
  Write-Information "`n->> Starting docker"
	sudo /usr/sbin/service docker start
}

Write-Information "`n->> Starting dev-env container"
sudo /usr/bin/docker start $ContainerName

Write-Information "`n->> Attaching to dev-env container"
sudo /usr/bin/docker container exec -it $ContainerName pwsh -c $Command

