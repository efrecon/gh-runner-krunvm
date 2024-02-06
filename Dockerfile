FROM efrecon/runner-krunvm.base:main

ARG INSTALL_VERSION=latest
ARG INSTALL_NAMESPACE=/opt/gh-runner-krunvm

COPY runner/*.sh ${INSTALL_NAMESPACE}/bin/
RUN chmod a+x "${INSTALL_NAMESPACE}/bin/*.sh" \
    && "${INSTALL_NAMESPACE}/bin/install.sh" -v -l /dev/stdout

ENTRYPOINT ["${INSTALL_NAMESPACE}/bin/entrypoint.sh"]
CMD ["./bin/Runner.Listener", "run", "--startuptype", "service"]