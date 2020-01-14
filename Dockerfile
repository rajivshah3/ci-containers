# Snapcraft image based on https://github.com/snapcore/snapcraft/blob/master/docker/stable.Dockerfile

# Use bionic instead of xenial because we use core18
FROM ubuntu:bionic as snapcraft-builder

# Grab dependencies
RUN apt-get update && apt-get dist-upgrade --yes && \
    apt-get install --yes curl jq squashfs-tools && \
    rm -rf /var/lib/apt/lists/*

# Grab the core snap from the stable channel and unpack it in the proper place
RUN curl -L $(curl -H 'X-Ubuntu-Series: 16' 'https://api.snapcraft.io/api/v1/snaps/details/core' | jq '.download_url' -r) --output core.snap && \
    mkdir -p /snap/core && unsquashfs -d /snap/core/current core.snap

# Grab the snapcraft snap from the stable channel and unpack it in the proper place
RUN curl -L $(curl -H 'X-Ubuntu-Series: 16' 'https://api.snapcraft.io/api/v1/snaps/details/snapcraft?channel=stable' | jq '.download_url' -r) --output snapcraft.snap && \
    mkdir -p /snap/snapcraft && unsquashfs -d /snap/snapcraft/current snapcraft.snap

# Create a snapcraft runner
RUN mkdir -p /snap/bin && \
    echo "#!/bin/sh" > /snap/bin/snapcraft && \
    snap_version="$(awk '/^version:/{print $2}' /snap/snapcraft/current/meta/snap.yaml)" && \
    echo "export SNAP_VERSION=\"$snap_version\"" >> /snap/bin/snapcraft && \
    echo 'exec "$SNAP/usr/bin/python3" "$SNAP/bin/snapcraft" "$@"' >> /snap/bin/snapcraft && \
    chmod +x /snap/bin/snapcraft


FROM node:10.18-stretch

# Copy snaps from builder
COPY --from=snapcraft-builder /snap/core /snap/core
COPY --from=snapcraft-builder /snap/snapcraft /snap/snapcraft
COPY --from=snapcraft-builder /snap/bin/snapcraft /snap/bin/snapcraft


# Install build dependencies
RUN apt-get update && apt-get dist-upgrade -y && \
    apt-get install -y git python \
    gcc-multilib g++-multilib \
    build-essential libssl-dev rpm \
    libsecret-1-dev software-properties-common apt-transport-https \
    libudev-dev libusb-1.0-0-dev locales sudo && \
    rm -rf /var/lib/apt/lists/*

# Build and install OpenSSL 1.0.2k
# Based on https://github.com/realm/realm-js/blob/master/Dockerfile
RUN curl -SL https://www.openssl.org/source/openssl-1.0.2k.tar.gz | tar -zxC / && \
    cd openssl-1.0.2k && \
    ./Configure -DPIC -fPIC -fvisibility=hidden -fvisibility-inlines-hidden \
    no-zlib-dynamic no-dso linux-x86_64 --prefix=/usr && make && make install_sw && \
    cd .. && rm -rf openssl-1.0.2k.tar.gz

# Use our version of OpenSSL instead of the Debian-provided one
ENV PATH "/usr/local/ssl:$PATH"

# Generate locale
# https://github.com/tianon/docker-brew-debian/issues/45#issuecomment-325235517
RUN echo "LC_ALL=en_US.UTF-8" >> /etc/environment && \
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    locale-gen en_US.UTF-8

# Set the proper environment
ENV LANG="en_US.UTF-8"
ENV LANGUAGE="en_US:en"
ENV LC_ALL="en_US.UTF-8"
ENV PATH="/snap/bin:$PATH"
ENV SNAP="/snap/snapcraft/current"
ENV SNAP_NAME="snapcraft"
ENV SNAP_ARCH="amd64"

VOLUME /dist

WORKDIR /app
