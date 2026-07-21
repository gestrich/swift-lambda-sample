# syntax = docker/dockerfile:experimental
# ================================
# Build image
# ================================

FROM swift:6.3.1-amazonlinux2023 as build

 RUN dnf -y install \
     git \
     libuuid-devel \
     libicu \
     libedit-devel \
     libxml2-devel \
     sqlite-devel \
     python3-devel \
     ncurses-devel \
     libcurl-devel \
     openssl-devel \
     tzdata \
     libtool \
     jq \
     tar \
     zip
     
# We use a stage directory to avoid strange problems with putting the Package.swift at root.
ARG AWS_ACCESS_KEY_ID
COPY ./Package.swift ./stage/Package.swift
WORKDIR "/stage"
RUN swift package reset

# Setup NetRC so package can get into our github
RUN --mount=type=secret,id=netrc cat /run/secrets/netrc > ~/.netrc && chmod 600 ~/.netrc

RUN swift package resolve

# TODO: Remove NetRC?
#RUN rm -rf ~/.ssh
