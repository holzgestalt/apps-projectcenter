# GNUstep-image.Dockerfile: the container image ProjectCenter's Archive
# builds GNUstep applications in (the Container way of a Linux target's
# distributions). GNUstep is built with clang and libobjc2 (ng-gnu-gnu) into
# /opt/gnustep and installed from its own package, projectcenter-gnustep,
# which Archive puts next to the application's package. See
# gnustep-image.sh for the steps.
#
# archive.sh builds it when the image is missing, once for each image name
# and platform:
#
#   docker build --platform linux/arm64 --build-arg BASE=debian:trixie \
#     -t projectcenter-gnustep:debian-arm64 <context>
#
# The context holds this file, gnustep-image.sh and sources/, with the
# source folders to build from (libobjc2, tools-make, libs-base, libs-gui,
# libs-back and a gtk4native* theme); the missing ones are cloned: from the
# holzgestalt forks where there is one (libs-base, libs-gui, GTK4Native),
# else from gnustep. THEME_URL= leaves the theme out.
#
# The image is made once and reused by every project: archive.sh rebuilds it
# only when it is missing or its org.gnustep.projectcenter.image label is not
# the version below (ImageVersion in PCDeployment.m), so raise both together
# whenever what the image holds changes.
#
# This file is part of GNUstep ProjectCenter.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

ARG BASE=debian:trixie
FROM ${BASE}

ARG LIBOBJC2_URL=https://github.com/gnustep/libobjc2.git
ARG LIBOBJC2_REF=
ARG MAKE_URL=https://github.com/gnustep/tools-make.git
ARG MAKE_REF=
ARG BASE_URL=https://github.com/holzgestalt/libs-base.git
ARG BASE_REF=
ARG GUI_URL=https://github.com/holzgestalt/libs-gui.git
ARG GUI_REF=
ARG BACK_URL=https://github.com/gnustep/libs-back.git
ARG BACK_REF=
ARG THEME_URL=https://github.com/holzgestalt/GTK4Native.git
ARG THEME_REF=

ENV PREFIX=/opt/gnustep

COPY gnustep-image.sh /usr/local/share/projectcenter/gnustep-image.sh
RUN sh /usr/local/share/projectcenter/gnustep-image.sh packages

COPY sources/ /sources/
RUN sh /usr/local/share/projectcenter/gnustep-image.sh gnustep
RUN sh /usr/local/share/projectcenter/gnustep-image.sh runtime

ENV GNUSTEP_MAKEFILES=/opt/gnustep/share/GNUstep/Makefiles \
    PKG_CONFIG_PATH=/opt/gnustep/lib/pkgconfig \
    PATH=/usr/local/bin:/opt/gnustep/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    CC=clang CXX=clang++ OBJC=clang
LABEL org.gnustep.projectcenter.image="3"
