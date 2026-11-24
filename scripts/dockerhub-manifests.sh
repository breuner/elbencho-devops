#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Join the per-architecture image digests into the Docker Hub tags. Each file
# in the digest directory is named "<flavor>-<arch>" and contains one
# sha256 digest. The Ubuntu 26.04 image also receives "latest" and the git tag.

set -euo pipefail

digest_dir=${1:?digest directory is required}
tag=${TAG:?TAG is required}
image=docker.io/breuner/elbencho

if ! [[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    echo "ERROR: tag is empty or not a container tag: ${tag}" >&2
    exit 1
fi

source_ref() {
    local name=$1
    local file=${digest_dir}/${name}
    local digest
    if [ ! -f "$file" ]; then
        echo "ERROR: missing digest file ${file}" >&2
        exit 1
    fi
    digest=$(tr -d '[:space:]' < "$file")
    case "$digest" in
        sha256:[0-9a-f][0-9a-f]*) ;;
        *)
            echo "ERROR: bad digest in ${file}" >&2
            exit 1
            ;;
    esac
    printf '%s@%s\n' "$image" "$digest"
}

publish() {
    local flavor=$1
    shift
    local arch sources=()
    for arch in amd64 arm64; do
        sources+=("$(source_ref "${flavor}-${arch}")")
    done
    if [ "${DOCKERHUB_DRY_RUN:-}" = 1 ]; then
        printf 'create'
        printf ' %s' "$@"
        printf ' %s' "${sources[@]}"
        printf '\n'
        return
    fi
    docker buildx imagetools create "$@" "${sources[@]}"
}

inspect_tag() {
    local ref=$1
    local raw
    if [ "${DOCKERHUB_DRY_RUN:-}" = 1 ]; then
        return
    fi
    raw=$(docker buildx imagetools inspect --raw "$ref")
    printf '%s\n' "$raw" | TAG_REF="$ref" python3 -c '
import json, os, sys
data = json.load(sys.stdin)
found = []
for manifest in data.get("manifests") or []:
    platform = manifest.get("platform") or {}
    arch = platform.get("architecture")
    if platform.get("os") == "linux" and arch in ("amd64", "arm64"):
        found.append(arch)
missing = [arch for arch in ("amd64", "arm64") if arch not in found]
if missing:
    sys.exit("ERROR: %s is missing %s" % (os.environ["TAG_REF"], ", ".join(missing)))
print("%s: %s" % (os.environ["TAG_REF"], " ".join(sorted(set(found)))))
'
}

publish ubuntu2604 \
    -t "${image}:master-ubuntu2604" \
    -t "${image}:latest" \
    -t "${image}:${tag}"
publish alpine -t "${image}:master-alpine"
publish cuda -t "${image}:master-ubuntu-cuda-multiarch"

inspect_tag "${image}:master-ubuntu2604"
inspect_tag "${image}:latest"
inspect_tag "${image}:${tag}"
inspect_tag "${image}:master-alpine"
inspect_tag "${image}:master-ubuntu-cuda-multiarch"
echo "Published container tags for ${tag}."
