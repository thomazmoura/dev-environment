echo "\n->> Starting dev-env container"
sudo /usr/bin/docker start dev-env

echo "\n->> Attaching to dev-env container"
sudo /usr/bin/docker container exec -it dev-env pwsh -c 'if( tmux ls 2> $null ) { tmuxa } else { vtmux }'
