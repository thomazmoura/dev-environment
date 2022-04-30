$NVS_HOME="$HOME/.nvs"
git clone https://github.com/jasongin/nvs $NVS_HOME
. "$NVS_HOME/nvs.ps1" install

nvs add lts
nvs add 12
nvs add 14
nvs add 16
nvs add 18

nvs auto on

nvs use lts

