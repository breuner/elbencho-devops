#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Create a draft release on breuner/elbencho, or leave an existing draft as it is.
# A published release for the tag stops the run. Release notes for a new draft are
# copied from the latest published stable release.

set -euo pipefail

: "${TAG:?TAG is required}"
: "${RELEASE_TITLE:?RELEASE_TITLE is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

repo="breuner/elbencho"

if [[ ! "$TAG" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: tag contains unsupported characters: ${TAG}" >&2
    exit 1
fi

if [ -z "$RELEASE_TITLE" ] || [[ "$RELEASE_TITLE" == *$'\n'* ]] || [[ "$RELEASE_TITLE" == *$'\r'* ]]; then
    echo "ERROR: release title is empty or contains a newline." >&2
    exit 1
fi

if ! gh api "repos/${repo}/git/ref/tags/${TAG}" > /dev/null; then
    echo "ERROR: tag not found on ${repo}: ${TAG}" >&2
    exit 1
fi

if release_json=$(gh release view "$TAG" --repo "$repo" --json isDraft,name,tagName 2> /dev/null); then
    is_draft=$(printf '%s' "$release_json" | jq -r .isDraft)
    if [ "$is_draft" != "true" ]; then
        echo "ERROR: ${repo} already has a published release for tag ${TAG}." >&2
        echo "That release was not modified." >&2
        exit 1
    fi
    echo "Reusing the existing draft for ${TAG}. Its title and notes were left unchanged."
    exit 0
fi

notes=$(mktemp)
trap 'rm -f "$notes"' EXIT

gh api "repos/${repo}/releases/latest" --jq '.body // ""' > "$notes"
latest_name=$(gh api "repos/${repo}/releases/latest" --jq '.tag_name')
echo "Copied release notes from the latest published stable release (${latest_name})."
if [ ! -s "$notes" ]; then
    printf 'Release notes from %s were empty.\n' "$latest_name" > "$notes"
fi

gh release create "$TAG" \
    --repo "$repo" \
    --draft \
    --verify-tag \
    --title "$RELEASE_TITLE" \
    --notes-file "$notes"

echo "Created draft release '${RELEASE_TITLE}' for ${TAG}."
