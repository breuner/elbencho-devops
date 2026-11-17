#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# GitHub-hosted runners have a small disk. The preinstalled tool cache is not
# needed to build elbencho.

set -euo pipefail

sudo rm -rf \
    /usr/share/dotnet \
    /usr/local/lib/android \
    /opt/ghc \
    /opt/hostedtoolcache \
    /usr/local/share/boost \
    ${AGENT_TOOLSDIRECTORY:+"$AGENT_TOOLSDIRECTORY"} \
    || true

df -h /
