#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# The arm64 image is built on a GitHub runner whose compiler defaults to a
# newer architecture than Cortex-A72 or Cortex-A78AE. Patch the checked-out
# Dockerfile so C and C++ use the same baseline as the static arm64 package,
# armv8-a+crc+crypto+simd. Assembly files keep their own .arch line, and a
# translation unit that already asks for SVE is left alone.

import base64
import sys
from pathlib import Path

# An output file ending in .s must not be treated as an assembly source, or
# the march flag is skipped.
wrapper = """#!/bin/sh
real=$1
shift
prev=
for a in "$@"; do
    case "$prev" in
        -o) ;;
        *)
            case "$a" in
                *.S|*.s|*+sve*) exec "$real" "$@" ;;
            esac
            ;;
    esac
    prev=$a
done
exec "$real" "$@" -march=armv8-a+crc+crypto+simd
"""
wrapper_b64 = base64.b64encode(wrapper.encode()).decode()

dockerfile = Path(
    sys.argv[1]
    if len(sys.argv) > 1
    else "elbencho/build_helpers/docker/Dockerfile.ubuntu2604.local")
text = dockerfile.read_text()
needle = "    cd /root/elbencho && \\\n"
insert = f"""    mkdir -p /usr/local/bin && \\
    echo {wrapper_b64} | base64 -d > /usr/local/bin/arm64-cc && \\
    chmod +x /usr/local/bin/arm64-cc && \\
    for cc in gcc g++ cc c++; do \\
        printf '%s\\n' '#!/bin/sh' 'exec /usr/local/bin/arm64-cc /usr/bin/'"$cc"' "$@"' \\
            > /usr/local/bin/$cc; \\
    done && \\
    chmod +x /usr/local/bin/gcc /usr/local/bin/g++ /usr/local/bin/cc /usr/local/bin/c++ && \\
    export PATH="/usr/local/bin:${{PATH}}" && \\
    printf '%s\\n' 'void fill(int *p, int n) {{ for (int i = 0; i < n; ++i) p[i] = i; }}' > /tmp/sve-check.c && \\
    /usr/local/bin/gcc -O3 -S -o /tmp/sve-check.asm /tmp/sve-check.c && \\
    /usr/local/bin/g++ -O3 -S -o /tmp/sve-check-cxx.asm -x c++ /tmp/sve-check.c && \\
    echo "arm64 gcc arch:" && grep -E '^[[:space:]]*\\.arch' /tmp/sve-check.asm || true && \\
    echo "arm64 g++ arch:" && grep -E '^[[:space:]]*\\.arch' /tmp/sve-check-cxx.asm || true && \\
    if grep -E 'index[[:space:]]+z|whilelo|ptrue|\\.arch_extension sve' /tmp/sve-check.asm /tmp/sve-check-cxx.asm; then \\
        echo "ERROR: the arm64 compiler still emits SVE." >&2; \\
        exit 1; \\
    fi && \\
    rm -f /tmp/sve-check.c /tmp/sve-check.asm /tmp/sve-check-cxx.asm && \\
"""
# Ubuntu and CUDA indent the build step. Alpine starts the RUN with it.
fallback = "RUN cd /root/elbencho && \\\n"
if needle in text:
    text = text.replace(needle, insert + needle, 1)
elif fallback in text:
    text = text.replace(fallback, "RUN " + insert + "cd /root/elbencho && \\\n", 1)
else:
    sys.exit(f"Dockerfile build step not found in {dockerfile}")
dockerfile.write_text(text)
