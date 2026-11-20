#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Start elbencho-pr-test.yml for open elbencho pull requests whose head commit
# has not been tested yet. A newer commit on the same request starts a new run,
# which cancels the previous one.

set -euo pipefail

script_dir=$(dirname "$(readlink -f "$0")")
source_repo=breuner/elbencho
workflow_repo=breuner/elbencho-devops
workflow=elbencho-pr-test.yml

# The workflow token can start runs in this repository, but it cannot read
# pull requests in breuner/elbencho. That listing uses the status token.
if [ -z "${ELBENCHO_STATUS_TOKEN:-}" ]; then
    echo "ELBENCHO_STATUS_TOKEN is required to list pull requests." >&2
    exit 1
fi
if ! prs=$(GH_TOKEN="$ELBENCHO_STATUS_TOKEN" gh pr list --repo "$source_repo" \
    --state open --limit 50 --json number,headRefOid); then
    echo "Could not list pull requests." >&2
    echo "ELBENCHO_STATUS_TOKEN needs Pull requests: Read on ${source_repo}." >&2
    exit 1
fi
runs=$(gh run list --repo "$workflow_repo" --workflow "$workflow" --limit 200 \
    --json displayTitle,status)

echo "$prs" | jq -c '.[]' | while read -r pr; do
    number=$(echo "$pr" | jq -r .number)
    sha=$(echo "$pr" | jq -r .headRefOid)
    title="PR ${number} ${sha}"
    if echo "$runs" | jq -e --arg title "$title" \
        'any(.[]; .displayTitle == $title)' >/dev/null; then
        echo "PR ${number} at ${sha} already has a test run."
        continue
    fi
    echo "Starting tests for PR ${number} at ${sha}."
    "$script_dir/pr-status.sh" pending "$sha" "pull request tests queued" \
        "https://github.com/${workflow_repo}/actions/workflows/${workflow}"
    gh workflow run "$workflow" --repo "$workflow_repo" \
        -f "ref=refs/pull/${number}/head" \
        -f "pr=${number}" \
        -f "sha=${sha}"
done
