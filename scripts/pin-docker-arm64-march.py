#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# The arm64 image is built on a GitHub runner whose compiler defaults to a
# newer architecture than Cortex-A78AE. That default emits SVE at -O3, and
# this CPU does not implement SVE. Patch the checked-out Dockerfile so C and
# C++ are compiled for armv8.2-a plus the extensions this CPU does have,
# including CRC and crypto for the AWS SDK. Assembly files keep their own
# .arch line, and a translation unit that already asks for SVE is left alone
# so optional kernels can still be built.

import sys
from pathlib import Path

dockerfile = Path(
    sys.argv[1]
    if len(sys.argv) > 1
    else "elbencho/build_helpers/docker/Dockerfile.ubuntu2604.local")
text = dockerfile.read_text()
needle = "    cd /root/elbencho && \\\n"
insert = r"""    mkdir -p /usr/local/bin && \
    march="-march=armv8.2-a+crc+crypto+fp16+dotprod+rdm+rcpc+flagm" && \
    echo "arm64 compiler march: $march" && \
    for cc in gcc g++ cc c++; do \
        real=/usr/bin/$cc; \
        printf '%s\n' '#!/bin/sh' \
            'for a in "$@"; do case "$a" in *.S|*.s|*+sve*) exec '"$real"' "$@";; esac; done' \
            'exec '"$real"' "$@" '"$march" \
            > /usr/local/bin/$cc; \
    done && \
    chmod +x /usr/local/bin/gcc /usr/local/bin/g++ /usr/local/bin/cc /usr/local/bin/c++ && \
    export PATH="/usr/local/bin:${PATH}" && \
    printf '%s\n' 'void fill(int *p, int n) { for (int i = 0; i < n; ++i) p[i] = i; }' > /tmp/sve-check.c && \
    /usr/local/bin/gcc -O3 -S -o /tmp/sve-check.s /tmp/sve-check.c && \
    if grep -E 'index[[:space:]]+z|whilelo|ptrue' /tmp/sve-check.s; then \
        echo "ERROR: the arm64 compiler still emits SVE." >&2; \
        exit 1; \
    fi && \
    rm -f /tmp/sve-check.c /tmp/sve-check.s && \
"""
if needle not in text:
    sys.exit(f"Dockerfile build step not found in {dockerfile}")
dockerfile.write_text(text.replace(needle, insert + needle, 1))
