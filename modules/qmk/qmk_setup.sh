python3 -m pip install --user -r /home/developer/.modules/qmk/requirements.txt
python3 -m pip install --user qmk 

export PATH="/home/developer/.local/bin:$PATH"
qmk setup

