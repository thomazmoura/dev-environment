FROM thomazmoura/dev-environment

USER root

# QMK requirements
COPY module /root/.modules/qmk
RUN chmod +x /root/.modules/qmk/qmk_install.sh && /root/.modules/qmk/qmk_install.sh

USER developer

CMD ["/opt/microsoft/powershell/7/pwsh", "-NoProfile", "-Command", "/home/developer/.modules/entrypoint/Start-DevSession.ps1 && tail -f /dev/null"]

