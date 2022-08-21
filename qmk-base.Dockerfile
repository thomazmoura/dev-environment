FROM thomazmoura/dev-environment:base

USER root

# QMK requirements
COPY modules/qmk/qmk_install.sh /root/.modules/qmk/qmk_install.sh
RUN chmod +x /root/.modules/qmk/qmk_install.sh && /root/.modules/qmk/qmk_install.sh

USER developer

COPY modules/qmk/requirements.txt /home/developer/.modules/qmk/requirements.txt
RUN python3 -m pip install --user -r /home/developer/.modules/qmk/requirements.txt

# Rust installation
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

