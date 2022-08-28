python3 -m pip install --user -r /home/developer/.modules/qmk/requirements.txt
python3 -m pip install --user qmk 

$env:PATH="$env:PATH`:/home/developer/.local/bin"
qmk setup

