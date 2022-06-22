echo "\n->> Starting dev-env container"
sudo docker start dev-env

echo "\n->> Attaching to dev-env container"
sudo docker container exec -it dev-env pwsh -c 'if( tmux ls 2> $null ) { tmuxa } else { vtmux }'
