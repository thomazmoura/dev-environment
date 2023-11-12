ARG DockerBase
FROM $DockerBase

USER root

# QMK requirements
COPY modules/qmk/qmk_install.sh /root/.modules/qmk/qmk_install.sh
RUN chmod +x /root/.modules/qmk/qmk_install.sh && /root/.modules/qmk/qmk_install.sh

# C requirements
RUN apt install clangd

USER developer

COPY --chown=developer:developer modules/qmk /home/developer/.modules/qmk
RUN chmod +x /home/developer/.modules/qmk/qmk_setup.sh && /home/developer/.modules/qmk/qmk_setup.sh

# Rust installation
COPY --chown=developer:developer modules/powershell /home/developer/.modules/powershell
COPY --chown=developer:developer modules/rust /home/developer/.modules/rust
RUN pwsh -NoProfile -File /home/developer/.modules/rust/Install-Rust.ps1

