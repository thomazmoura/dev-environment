FROM thomazmoura/dev-environment

USER root

# QMK requirements
COPY qmk_install.sh /root/.modules/qmk/install.sh
RUN chmod +x /root/.modules/qmk/qmk_install.sh && /root/.modules/qmk/qmk_install.sh

USER developer

COPY requirements.txt /home/developer/.modules/qmk/requirements.txt
RUN python3 -m pip install --user -r /home/developer/.modules/qmk/requirements.txt

CMD ["/opt/microsoft/powershell/7/pwsh", "-NoProfile", "-Command", "/home/developer/.modules/entrypoint/Start-DevSession.ps1 && tail -f /dev/null"]

