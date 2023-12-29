# syntax = docker/dockerfile:experimental
# ================================
# Build image
# ================================

FROM swift:5.9.2-amazonlinux2 as build
  
 RUN yum -y install \
     git \
     libuuid-devel \
     libicu-devel \
     libedit-devel \
     libxml2-devel \
     sqlite-devel \
     python-devel \
     ncurses-devel \
     curl-devel \
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
