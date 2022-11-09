param(
  [String]$Command='if( tmux ls 2> $null ) { tmuxa } else { vtmux }'
)

Write-Information "\n->> Starting dev-env container"
sudo docker start dev-env

Write-Information "\n->> Attaching to dev-env container"
sudo docker container exec -it dev-env pwsh -c $Command

