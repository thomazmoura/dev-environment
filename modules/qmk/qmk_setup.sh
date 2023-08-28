python3 -m pipx install -r /home/developer/.modules/qmk/requirements.txt
python3 -m pipx install qmk 

export PATH="/home/developer/.local/bin:$PATH"
qmk setup

