#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Write the failed-job console to the run summary and print one short line
# for the commit status. Prints nothing when no failed log is available.

set -euo pipefail

log=$(gh run view "${GITHUB_RUN_ID}" --repo "${GITHUB_REPOSITORY}" --log-failed 2>/dev/null || true)
if [ -z "$log" ]; then
    exit 0
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "## Failed test output"
        echo
        echo '```'
        printf '%s\n' "$log" | tail -n 120
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
fi

printf '%s\n' "$log" | grep -E 'ERROR:|error:|not ok|FAIL:' | tail -n 1 | cut -c 1-140
