#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Upload files to the draft release for TAG. Refuses to touch a published release.
# --clobber replaces an asset of the same name from an earlier attempt.

set -euo pipefail

: "${TAG:?TAG is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

repo="breuner/elbencho"

if [ "$#" -lt 1 ]; then
    echo "ERROR: no files to upload." >&2
    exit 1
fi

for file in "$@"; do
    if [ ! -s "$file" ]; then
        echo "ERROR: artifact is missing or empty: ${file}" >&2
        exit 1
    fi
    echo "Artifact: ${file} ($(du -h "$file" | awk '{print $1}'))"
done

is_draft=$(gh release view "$TAG" --repo "$repo" --json isDraft --jq .isDraft)
if [ "$is_draft" != "true" ]; then
    echo "ERROR: the release for ${TAG} is not a draft. Nothing was uploaded." >&2
    exit 1
fi

gh release upload "$TAG" --repo "$repo" --clobber "$@"
echo "Uploaded $# file(s) to the draft for ${TAG}."
