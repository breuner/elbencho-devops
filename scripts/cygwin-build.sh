#!/bin/bash
#
# Build elbencho's Windows zip from a Cygwin shell.
# Argument 1 is the elbencho source tree as a Cygwin path.

# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

root=$1
git config --global --add safe.directory "$root"
cd "$root"

# Git Bash exports MSYSTEM and a PATH whose make, git and bash use /d/a paths.
# Those paths do not exist for Cygwin. Drop that environment and prefer Cygwin.
unset MSYSTEM MSYSTEM_CARCH MSYSTEM_CHOST MSYSTEM_PREFIX MSYS_NO_PATHCONV

# ftxui enables ccache when a ccache binary is on PATH. The Windows runner's
# ccache cannot execute Cygwin's /usr/bin/c++.exe symlink, so a Cygwin
# pass-through has to come first. It just runs the compiler.
mkdir -p .ci-bin
cat > .ci-bin/ccache <<'EOF'
#!/bin/bash
exec "$@"
EOF
chmod +x .ci-bin/ccache
cp .ci-bin/ccache .ci-bin/ccache.exe
export PATH="$(pwd)/.ci-bin:/usr/local/bin:/usr/bin:/bin:${PATH}"
hash -r
echo "pwd=$(pwd)"
echo "make=$(command -v make) git=$(command -v git) bash=$(command -v bash)"

./build_helpers/cygwin/create_package.sh
