FROM ubuntu:24.04@sha256:224a1869083a311ef3f13648a154ba79832fbef6364d31493642ca03082da254 AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        cmake \
        g++ \
        libfcitx5core-dev \
        ninja-build \
    && rm -rf /var/lib/apt/lists/*

FROM build AS x11-e2e

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        at-spi2-core \
        dbus-x11 \
        fcitx5 \
        fcitx5-config-qt \
        fcitx5-frontend-gtk3 \
        fonts-wqy-zenhei \
        libgtk-3-dev \
        netpbm \
        python3-pyatspi \
        x11-apps \
        x11-utils \
        xdotool \
        xvfb \
    && rm -rf /var/lib/apt/lists/*

FROM x11-e2e AS package-build

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        debhelper \
        dpkg-dev \
        fakeroot \
        lintian \
    && rm -rf /var/lib/apt/lists/*

FROM ubuntu:24.04@sha256:224a1869083a311ef3f13648a154ba79832fbef6364d31493642ca03082da254 AS package-test

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        at-spi2-core \
        binutils \
        ca-certificates \
        cmake \
        dbus-x11 \
        fcitx5 \
        fcitx5-config-qt \
        fcitx5-frontend-gtk3 \
        fonts-wqy-zenhei \
        libglib2.0-bin \
        libgtk-3-0 \
        netpbm \
        python3-pyatspi \
        x11-apps \
        x11-utils \
        xdotool \
        xvfb \
    && rm -rf /var/lib/apt/lists/*
