#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Build one elbencho configuration and run its tests.
# Argument 1 is without-s3, s3, or s3-crt.
# Argument 2 is the elbencho source directory.

set -euo pipefail

mode=${1:?mode is required: without-s3, s3, or s3-crt}
source_dir=${2:?elbencho source directory is required}
source_dir=$(readlink -f "$source_dir")
tmp=${RUNNER_TEMP:-/tmp}/elbencho-pr-${mode}
minio_pid=""

cleanup() {
    if [ -x "$source_dir/bin/elbencho" ]; then
        "$source_dir/bin/elbencho" --hosts localhost:1711,localhost:1712 --quit >/dev/null 2>&1 || true
    fi
    if [ -n "$minio_pid" ] && kill -0 "$minio_pid" >/dev/null 2>&1; then
        kill "$minio_pid" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

wait_for_port() {
    local port=$1
    local attempt
    for attempt in $(seq 1 50); do
        if (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    echo "ERROR: nothing is listening on 127.0.0.1:${port}" >&2
    return 1
}

run_s3_commands() {
    local minio="$tmp/minio"
    local data="$tmp/minio-data"
    local port=11000
    local console=11001
    local key=elbenchotest
    local secret=elbenchotestsecret

    echo "Downloading the libreFS S3 server..."
    curl -fLsS -o "$minio" \
        https://github.com/libreFS/libreFS/releases/latest/download/librefs-linux-amd64
    chmod +x "$minio"
    mkdir -p "$data"
    MINIO_ROOT_USER=$key MINIO_ROOT_PASSWORD=$secret \
        "$minio" server "$data" \
        --address "127.0.0.1:${port}" \
        --console-address "127.0.0.1:${console}" \
        > "$tmp/minio.out" 2>&1 &
    minio_pid=$!
    wait_for_port "$port"

    echo "Running the single-host S3 example..."
    "$source_dir/bin/elbencho" \
        --s3endpoints "http://127.0.0.1:${port}" \
        --s3key "$key" --s3secret "$secret" \
        'mybucket/subdir/obj[1-3]' \
        -d -w --stat -r -F -D -t 5 -s 10m -b 5m --sharesize 1

    echo "Running the multi-service S3 example..."
    "$source_dir/bin/elbencho" --service --port 1711
    "$source_dir/bin/elbencho" --service --port 1712
    wait_for_port 1711
    wait_for_port 1712
    "$source_dir/bin/elbencho" \
        --s3endpoints "http://127.0.0.1:${port}" \
        --s3key "$key" --s3secret "$secret" \
        'mybucket2' --s3objprefix subdir2/ \
        -d -w -r -F -D --verify 1 -t 2 -s 20m -b 10m --s3mpusizevar 1m \
        --hosts "localhost:[1711,1712]"
}

cd "$source_dir"
git log -1 --oneline

make_flags=(BACKTRACE_SUPPORT=0 IBVERBS_SUPPORT=0 RDMACM_SUPPORT=0 USE_MIMALLOC=1)
example_args=(-b)
case "$mode" in
    without-s3)
        make_flags+=(S3_SUPPORT=0)
        ;;
    s3)
        make_flags+=(S3_SUPPORT=1)
        ;;
    s3-crt)
        make_flags+=(S3_SUPPORT=1 S3_AWSCRT=1)
        example_args+=(-r)
        ;;
    *)
        echo "ERROR: unknown mode: ${mode}" >&2
        exit 1
        ;;
esac

echo "Building: ${make_flags[*]}"
make -j "$(nproc)" "${make_flags[@]}"
bin/elbencho --version
bin/elbencho --hosts localhost:1711,localhost:1712 --quit >/dev/null 2>&1 || true

mkdir -p "$tmp/tests" "$tmp/examples"
tests/run-tests.sh -a -j 4 -T "$tmp/tests"
tools/test-examples.sh "${example_args[@]}" "$tmp/examples"

if [ "$mode" = s3 ]; then
    run_s3_commands
fi
