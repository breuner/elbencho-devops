#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Build one elbencho rpm or deb with S3, SPDK, rdmacm and libfabric.
# KIND=rpm and IMAGE set a container (rockylinux:8, rockylinux:9, rockylinux:10).
# KIND=deb runs on the host, which is the matching Ubuntu runner.
# Compiler wrappers drop -march and -mcpu from the build, then append MARCH.
# That keeps a runner CPU such as Neoverse or -march=native from winning.
# On Arm, uname -p is reported as unknown so SPDK builds DPDK for generic
# armv8-a instead of the runner CPU. The runner CPU's atomics do not assemble
# for that baseline and would not run on older Arm machines.

set -euo pipefail

if [ -n "${IMAGE:-}" ] && [ -z "${REPO_PACKAGE_INSIDE:-}" ]; then
    root=$(cd "$(dirname "$0")/.." && pwd)
    exec docker run --rm --pull always \
        -e REPO_PACKAGE_INSIDE=1 \
        -e KIND -e MARCH -e SOURCE=/work/elbencho -e OUTPUT=/work/dist \
        -v "$root:/work" \
        -w /work \
        "$IMAGE" \
        bash /work/scripts/repo-package.sh
fi

kind=${KIND:?KIND is required}
march=${MARCH:?MARCH is required}
source_dir=$(cd "${SOURCE:-elbencho}" && pwd)
mkdir -p "${OUTPUT:-dist}"
output_dir=$(cd "${OUTPUT:-dist}" && pwd)

if [ "$(id -u)" -eq 0 ]; then
    sudo=()
else
    sudo=(sudo)
fi

run_root() {
    "${sudo[@]}" "$@"
}

install_compiler_wrappers() {
    local real_gcc real_gxx real_cc real_cxx
    real_gcc=$(command -v gcc)
    real_gxx=$(command -v g++)
    real_cc=$(command -v cc || true)
    real_cxx=$(command -v c++ || true)
    real_cc=${real_cc:-$real_gcc}
    real_cxx=${real_cxx:-$real_gxx}

    run_root mkdir -p /usr/local/bin
    run_root tee /usr/local/bin/repo-cc >/dev/null <<EOF
#!/bin/bash
real=\$1
shift
prev=
for a in "\$@"; do
    case "\$prev" in
        -o) ;;
        *)
            case "\$a" in
                *.S|*.s|*+sve*) exec "\$real" "\$@" ;;
            esac
            ;;
    esac
    prev=\$a
done
link=1
skip=0
args=()
for a in "\$@"; do
    if [ "\$skip" = 1 ]; then
        skip=0
        continue
    fi
    case "\$a" in
        -mcpu|-march)
            skip=1
            ;;
        -mcpu=*|-march=*)
            ;;
        -c|-S|-E|-M|-MM)
            link=0
            args+=("\$a")
            ;;
        *)
            args+=("\$a")
            ;;
    esac
done
if [ "\$link" = 1 ]; then
    exec "\$real" "\${args[@]}" -march=${march} -llz4
fi
exec "\$real" "\${args[@]}" -march=${march}
EOF
    run_root chmod 755 /usr/local/bin/repo-cc
    local cc target
    for cc in gcc g++ cc c++; do
        case "$cc" in
            gcc) target=$real_gcc ;;
            g++) target=$real_gxx ;;
            cc) target=$real_cc ;;
            c++) target=$real_cxx ;;
        esac
        printf '%s\n' '#!/bin/sh' "exec /usr/local/bin/repo-cc ${target} \"\$@\"" \
            | run_root tee "/usr/local/bin/${cc}" >/dev/null
        run_root chmod 755 "/usr/local/bin/${cc}"
    done
    if [[ "$march" == armv8* ]]; then
        # SPDK selects DPDK's native platform unless uname -p is "unknown".
        run_root tee /usr/local/bin/uname >/dev/null <<'EOF'
#!/bin/sh
if [ "$1" = "-p" ] || [ "$1" = "--processor" ]; then
    echo unknown
    exit 0
fi
exec /usr/bin/uname "$@"
EOF
        run_root chmod 755 /usr/local/bin/uname
    fi
    export PATH="/usr/local/bin:${PATH}"

    local tmp
    tmp=$(mktemp -d)
    printf '%s\n' 'void fill(int *p, int n) { for (int i = 0; i < n; ++i) p[i] = i; }' > "$tmp/probe.c"
    /usr/local/bin/gcc -O3 -S -o "$tmp/probe.s" "$tmp/probe.c"
    /usr/local/bin/g++ -O3 -S -o "$tmp/probe-cxx.s" -x c++ "$tmp/probe.c"
    echo "gcc arch:" && grep -E '^[[:space:]]*\.arch' "$tmp/probe.s" || true
    echo "g++ arch:" && grep -E '^[[:space:]]*\.arch' "$tmp/probe-cxx.s" || true
    case "$march" in
        armv8*)
            if grep -E 'index[[:space:]]+z|whilelo|ptrue|\.arch_extension sve' \
                    "$tmp/probe.s" "$tmp/probe-cxx.s"; then
                echo "ERROR: the compiler still emits SVE." >&2
                exit 1
            fi
            ;;
    esac
    rm -rf "$tmp"
}

install_static_boost() {
    local version=1.83.0
    local underscore=1_83_0
    curl -fsSL -o /tmp/boost.tar.gz \
        "https://archives.boost.io/release/${version}/source/boost_${underscore}.tar.gz"
    tar -C /tmp -xzf /tmp/boost.tar.gz
    (
        cd "/tmp/boost_${underscore}"
        ./bootstrap.sh --with-libraries=json,program_options,thread,filesystem,system,regex,chrono,atomic,container
        ./b2 -j "$(nproc)" link=static runtime-link=shared variant=release install
    )
    rm -rf "/tmp/boost_${underscore}" /tmp/boost.tar.gz /usr/local/lib/libboost_*.so*
    export LIBRARY_PATH="/usr/local/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
    export CPATH="/usr/local/include${CPATH:+:$CPATH}"
    export CPLUS_INCLUDE_PATH="/usr/local/include${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
}

install_meson() {
    local py=python3
    if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)'; then
        run_root dnf install -y python3.11 python3.11-pip
        py=python3.11
    fi
    if ! "$py" -m pip --version >/dev/null 2>&1; then
        if command -v dnf >/dev/null 2>&1; then
            run_root dnf install -y python3-pip
        else
            run_root apt-get install -y python3-pip
        fi
    fi
    # --ignore-installed: Ubuntu already has these from apt, and pip cannot
    # uninstall a distro package that has no RECORD file.
    run_root "$py" -m pip install --break-system-packages --ignore-installed \
        meson ninja pyelftools jinja2 tabulate \
        || run_root "$py" -m pip install --ignore-installed meson ninja pyelftools jinja2 tabulate
    if [ "$py" != python3 ]; then
        run_root ln -sfn "$(command -v "$py")" /usr/local/bin/python3
        run_root ln -sfn "$(command -v "$py")" /usr/local/bin/python
    fi
    hash -r
    command -v meson
    command -v ninja
}

prepare_rpm() {
    run_root dnf install -y dnf-plugins-core
    if run_root dnf repolist --all | awk '{ print $1 }' | grep -Eq '^(powertools|PowerTools)$'; then
        run_root dnf config-manager --set-enabled powertools || \
            run_root dnf config-manager --set-enabled PowerTools
    else
        run_root dnf config-manager --set-enabled crb
    fi
    # curl-minimal is already installed in the Rocky images and conflicts with curl.
    run_root dnf install -y --allowerasing \
        autoconf automake gcc gcc-c++ make cmake git libtool patch pkgconf \
        libaio-devel libcurl-devel ncurses-devel numactl-devel openssl-devel \
        libuuid-devel zlib-devel rdma-core-devel \
        nasm diffutils findutils tar gzip which curl ca-certificates \
        rpm-build python3 python3-pip lz4-devel
    local gcc_major
    gcc_major=$(gcc -dumpversion | cut -d. -f1)
    if [ "$gcc_major" -lt 11 ]; then
        run_root dnf install -y gcc-toolset-13
        set +u
        # shellcheck disable=SC1091
        source /opt/rh/gcc-toolset-13/enable
        set -u
        export LDFLAGS_EXTRA="-static-libstdc++ -static-libgcc ${LDFLAGS_EXTRA:-}"
    fi
    if [ -e /usr/include/boost/json.hpp ]; then
        run_root dnf install -y boost-devel
    else
        install_static_boost
    fi
    install_meson
}

prepare_deb() {
    export DEBIAN_FRONTEND=noninteractive
    run_root apt-get update
    run_root apt-get install -y \
        autoconf automake build-essential cmake debhelper devscripts fakeroot git \
        libaio-dev libboost-filesystem-dev libboost-json-dev libboost-program-options-dev \
        libboost-thread-dev libcurl4-openssl-dev libibverbs-dev libncurses-dev libnuma-dev \
        librdmacm-dev libssl-dev libtool lintian nasm patch pkg-config \
        python3 python3-pip python3-pyelftools python3-jinja2 python3-tabulate \
        uuid-dev zlib1g-dev ca-certificates curl liblz4-dev
    install_meson
}

build_and_install() {
    cd "$source_dir"
    if [ -n "${REPO_PACKAGE_INSIDE:-}" ]; then
        git config --global --add safe.directory "$source_dir" || true
    fi
    make -j "$(nproc)" \
        S3_SUPPORT=1 SPDK_SUPPORT=1 IBVERBS_SUPPORT=1 RDMACM_SUPPORT=1 \
        LIBFABRIC_SUPPORT=1 BUILD_LIBFABRIC=1
    local pkg
    shopt -s nullglob
    if [ "$kind" = rpm ]; then
        make rpm
        local candidate
        pkg=
        for candidate in packaging/RPMS/*/*.rpm; do
            case "$candidate" in
                *debuginfo*|*debugsource*) continue ;;
            esac
            pkg=$candidate
        done
    else
        make deb
        local candidate
        pkg=
        for candidate in packaging/elbencho_*.deb; do
            case "$candidate" in
                *dbgsym*) continue ;;
            esac
            pkg=$candidate
        done
    fi
    shopt -u nullglob
    if [ -z "$pkg" ] || [ ! -f "$pkg" ]; then
        echo "ERROR: package was not produced." >&2
        find packaging \( -type f \( -name '*.rpm' -o -name '*.deb' \) \) >&2 || true
        exit 1
    fi
    echo "Package: $pkg"
    if [ "$kind" = rpm ]; then
        run_root dnf install -y "$PWD/$pkg"
    else
        run_root apt-get install -y "./$pkg"
    fi
    /usr/bin/elbencho --version
    mkdir -p "$output_dir"
    cp -a "$pkg" "$output_dir/"
    echo "Saved $(basename "$pkg") to $output_dir"
}

case "$kind" in
    rpm) prepare_rpm ;;
    deb) prepare_deb ;;
    *)
        echo "ERROR: KIND must be rpm or deb, got: $kind" >&2
        exit 1
        ;;
esac
install_compiler_wrappers
build_and_install
