#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Record a commit status on breuner/elbencho. Does nothing when
# ELBENCHO_STATUS_TOKEN is unset. A missing permission is reported and does
# not fail the caller: the test result remains the workflow result.

set -euo pipefail

state=${1:?state is required}
sha=${2:?commit sha is required}
description=${3:?description is required}
target_url=${4:-}
description=${description:0:140}

if [ -z "${ELBENCHO_STATUS_TOKEN:-}" ] || [ -z "$sha" ]; then
    echo "Commit status was not recorded."
    exit 0
fi

args=(
    --method POST
    -f "state=${state}"
    -f "context=elbencho-pr-test"
    -f "description=${description}"
)
if [ -n "$target_url" ]; then
    args+=(-f "target_url=${target_url}")
fi

if ! GH_TOKEN="$ELBENCHO_STATUS_TOKEN" gh api "${args[@]}" \
    "/repos/breuner/elbencho/statuses/${sha}" >/dev/null; then
    echo "WARNING: could not record the commit status." >&2
    echo "The token needs Commit statuses: Read and write on breuner/elbencho." >&2
fi
