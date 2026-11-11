ARG ARCH="amd64"
ARG OS="linux"
# YugabyteDB: a UBI9 base, which can be a hardened one, instead of busybox.
ARG BASE_IMAGE="registry.access.redhat.com/ubi9/ubi-minimal:latest"
FROM ${BASE_IMAGE} AS base

ARG ARCH="amd64"
ARG OS="linux"
# The FIPS release binary of this fork (see FIPS-RELEASE.md).
COPY .build/${OS}-${ARCH}/node_exporter /bin/node_exporter
COPY LICENSE NOTICE /licenses/node_exporter/
# Package repo definitions of a curated base can't ship in a published image.
RUN rm -rf /etc/yum.repos.d/rf-* && \
    /bin/node_exporter --version 2>&1 | grep -E '^[[:space:]]*tags:.*fips140v1\.0'

# One layer, so the deleted repo files are not left in a lower layer.
FROM scratch
COPY --from=base / /

ARG BASE_IMAGE
LABEL maintainer="YugabyteDB, Inc."
LABEL org.opencontainers.image.authors="The Prometheus Authors, YugabyteDB, Inc."
LABEL org.opencontainers.image.vendor="YugabyteDB, Inc."
LABEL org.opencontainers.image.title="node_exporter"
LABEL org.opencontainers.image.description="Prometheus exporter for hardware and OS metrics exposed by *NIX kernels, built with the Go FIPS 140-3 module"
LABEL org.opencontainers.image.source="https://github.com/yugabyte/node_exporter"
LABEL org.opencontainers.image.url="https://github.com/yugabyte/node_exporter"
LABEL org.opencontainers.image.documentation="https://github.com/yugabyte/node_exporter/blob/yb-master/FIPS-RELEASE.md"
LABEL org.opencontainers.image.licenses="Apache License 2.0"
LABEL org.opencontainers.image.base.name="${BASE_IMAGE}"
LABEL io.prometheus.image.variant="ubi9-fips"

ARG USER="10001"
USER        ${USER}
ENTRYPOINT  [ "/bin/node_exporter" ]
