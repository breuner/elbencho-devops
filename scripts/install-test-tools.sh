#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Tools required by tests/run-tests.sh -a on a GitHub-hosted Ubuntu runner.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo apt-get install -y perl jq python3 unzip curl ca-certificates

if ! command -v aws > /dev/null 2>&1; then
    case "$(uname -m)" in
        x86_64) aws_arch=x86_64 ;;
        aarch64) aws_arch=aarch64 ;;
        *)
            echo "ERROR: no AWS CLI build for $(uname -m)" >&2
            exit 1
            ;;
    esac
    tmp=$(mktemp -d)
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o "$tmp/aws.zip"
    unzip -q "$tmp/aws.zip" -d "$tmp"
    sudo "$tmp/aws/install"
    rm -rf "$tmp"
fi

for cmd in prove jq timeout python3 aws; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "ERROR: required command not found: ${cmd}" >&2
        exit 1
    fi
done
