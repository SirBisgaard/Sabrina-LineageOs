FROM debian:trixie@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6

ARG UID=1000
ARG GID=1000
ARG DEBIAN_SNAPSHOT=20261111T000000Z
ARG REPO_LAUNCHER_SHA256=05f571deafd6ed6da0d20fa707dde29aa5624dbf35553d697a40dbdd4c8d178a

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN rm -f /etc/apt/sources.list.d/debian.sources \
 && printf '%s\n' \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT trixie main" \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT trixie-updates main" \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/$DEBIAN_SNAPSHOT trixie-security main" \
      > /etc/apt/sources.list \
 && apt-get -o Acquire::Retries=5 update \
 && apt-get install -y --no-install-recommends \
      bc bison brotli build-essential ca-certificates ccache cpio curl e2fsprogs file flex \
      g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick \
      lib32readline-dev lib32z1-dev libelf-dev libncurses-dev libsdl1.2-dev libssl-dev \
      libxml2 libxml2-utils lz4 lzop openssl pngcrush procps python-is-python3 python3 rsync \
      schedtool shellcheck squashfs-tools unzip xsltproc xz-utils zip zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL 'https://gerrit.googlesource.com/git-repo/+/refs/tags/v2.71/repo?format=TEXT' | base64 -d > /usr/local/bin/repo \
 && echo "$REPO_LAUNCHER_SHA256  /usr/local/bin/repo" | sha256sum -c - \
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
