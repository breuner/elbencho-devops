#!/bin/bash
#
# Run the default elbencho test suite against the Cygwin build.
# Argument 1 is the elbencho source tree as a Cygwin path.
# Argument 2 is the temporary directory as a Cygwin path.

# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

root=$1
tmp=$2
cd "$root"
test -x bin/elbencho.exe
command -v prove
command -v jq
command -v timeout

tests/run-tests.sh -j 4 -T "$tmp"
