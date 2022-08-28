ARG DockerBase
FROM $DockerBase

USER root

# QMK requirements
COPY modules/qmk/qmk_install.sh /root/.modules/qmk/qmk_install.sh
RUN chmod +x /root/.modules/qmk/qmk_install.sh && /root/.modules/qmk/qmk_install.sh

USER developer

COPY modules/qmk/requirements.txt /home/developer/.modules/qmk/requirements.txt
RUN python3 -m pip install --user -r /home/developer/.modules/qmk/requirements.txt \
  && python3 -m pip install --user qmk 

# Rust installation
COPY modules/powershell /home/developer/.modules/powershell
COPY modules/rust /home/developer/.modules/rust
RUN pwsh -NoProfile -File /home/developer/.modules/rust/Install-Rust.ps1

