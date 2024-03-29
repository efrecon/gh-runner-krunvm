# syntax=docker/dockerfile:1
ARG VERSION=main
ARG DISTRO=fedora
FROM ghcr.io/efrecon/runner-krunvm-base-${DISTRO}:${VERSION}

ARG INSTALL_VERSION=latest
ARG INSTALL_NAMESPACE=/opt/gh-runner-krunvm

COPY runner/*.sh ${INSTALL_NAMESPACE}/bin/
# Redundant, but this makes this image more standalone.
COPY lib/*.sh ${INSTALL_NAMESPACE}/lib/
RUN chmod a+x ${INSTALL_NAMESPACE}/bin/*.sh \
    && "${INSTALL_NAMESPACE}/bin/install.sh" -v

ENTRYPOINT ["${INSTALL_NAMESPACE}/bin/entrypoint.sh"]
CMD ["./bin/Runner.Listener", "run", "--startuptype", "service"]