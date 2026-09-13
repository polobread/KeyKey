FROM ubuntu:22.04@sha256:829f6df217bcbae2b371026e81711d1a787c61b2967ad09d015063663ebafbf7 AS build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        cmake \
        g++ \
        libfcitx5core-dev \
        ninja-build \
    && rm -rf /var/lib/apt/lists/*

FROM build AS package-build

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        debhelper \
        dpkg-dev \
        fakeroot \
        lintian \
    && rm -rf /var/lib/apt/lists/*

FROM ubuntu:22.04@sha256:829f6df217bcbae2b371026e81711d1a787c61b2967ad09d015063663ebafbf7 AS package-test

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        binutils \
        ca-certificates \
        cmake \
    && rm -rf /var/lib/apt/lists/*
