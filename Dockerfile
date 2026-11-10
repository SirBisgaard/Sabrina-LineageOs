FROM debian:trixie

ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bc bison brotli build-essential ca-certificates ccache cpio curl e2fsprogs file flex \
      g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick \
      lib32readline-dev lib32z1-dev libelf-dev libncurses-dev libsdl1.2-dev libssl-dev \
      libxml2 libxml2-utils lz4 lzop openssl pngcrush procps python-is-python3 python3 rsync \
      schedtool squashfs-tools unzip xsltproc xz-utils zip zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
 && chmod 755 /usr/local/bin/repo

RUN groupadd -o -g "$GID" builder \
 && useradd -m -o -u "$UID" -g "$GID" -s /bin/bash builder

COPY --chown=builder:builder overlay /opt/sabrina/overlay
COPY --chown=builder:builder tools /opt/sabrina/tools
COPY --chown=builder:builder patches /opt/sabrina/patches

USER builder
RUN git config --global user.name "Sabrina Builder" \
 && git config --global user.email "builder@localhost" \
 && git config --global color.ui false \
 && git lfs install --skip-repo

WORKDIR /work
ENTRYPOINT ["/opt/sabrina/tools/build.sh"]
