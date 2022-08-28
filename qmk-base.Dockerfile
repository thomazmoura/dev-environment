ARG DockerBase
FROM $DockerBase

USER root

# QMK requirements
COPY modules/qmk/qmk_install.sh /root/.modules/qmk/qmk_install.sh
RUN chmod +x /root/.modules/qmk/qmk_install.sh && /root/.modules/qmk/qmk_install.sh

USER developer

COPY modules/qmk /home/developer/.modules/qmk
RUN chmod +x /home/developer/.modules/qmk/qmk_setup.sh && /home/developer/.modules/qmk/qmk_setup.sh

# Rust installation
COPY modules/powershell /home/developer/.modules/powershell
COPY modules/rust /home/developer/.modules/rust
RUN pwsh -NoProfile -File /home/developer/.modules/rust/Install-Rust.ps1

