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

# gh release upload labels every .tar.gz as application/x-gtar. Safari then
# saves the download as .tar. application/octet-stream keeps the asset name.
tar_gz=()
other=()
for file in "$@"; do
    case "$file" in
        *.tar.gz) tar_gz+=("$file") ;;
        *) other+=("$file") ;;
    esac
done

if [ "${#other[@]}" -gt 0 ]; then
    gh release upload "$TAG" --repo "$repo" --clobber "${other[@]}"
fi

if [ "${#tar_gz[@]}" -gt 0 ]; then
    release_id=$(gh api graphql -f query='
        query($tag: String!) {
          repository(owner: "breuner", name: "elbencho") {
            release(tagName: $tag) { databaseId }
          }
        }' -f tag="$TAG" --jq '.data.repository.release.databaseId')
    if [ -z "$release_id" ] || [ "$release_id" = "null" ]; then
        echo "ERROR: could not find the release id for ${TAG}." >&2
        exit 1
    fi
    for file in "${tar_gz[@]}"; do
        name=$(basename "$file")
        existing=$(gh release view "$TAG" --repo "$repo" --json assets \
            --jq ".assets[] | select(.name==\"${name}\") | .apiUrl")
        if [ -n "$existing" ]; then
            gh api --method DELETE "${existing#https://api.github.com/}" >/dev/null
        fi
        gh api --method POST \
            -H "Accept: application/vnd.github+json" \
            -H "Content-Type: application/octet-stream" \
            --input "$file" \
            "repos/${repo}/releases/${release_id}/assets?name=${name}" \
            --jq '"Uploaded \( .name ) as \( .content_type )."'
    done
fi

echo "Uploaded $# file(s) to the draft for ${TAG}."
