#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Replace the elbencho GitHub Pages package repository with the packages in
# the artifact directory. The site contains only this build. The push updates
# the gh-pages branch and no other branch.

set -euo pipefail

artifacts=${1:?artifact directory is required}
tag=${TAG:?TAG is required}
token=${ELBENCHO_RELEASE_TOKEN:?ELBENCHO_RELEASE_TOKEN is required}
key_text=${ELBENCHO_REPO_GPG_KEY:?ELBENCHO_REPO_GPG_KEY is required}

site=$(mktemp -d)
trap 'rm -rf "$site"' EXIT

place() {
    local name=$1 dir=$2
    local src file
    src=${artifacts}/${name}
    shopt -s nullglob
    file=("${src}"/*)
    shopt -u nullglob
    if [ "${#file[@]}" -ne 1 ]; then
        echo "ERROR: expected one package in ${src}." >&2
        ls -la "$src" >&2 || true
        exit 1
    fi
    mkdir -p "$dir"
    cp -a "${file[0]}" "$dir/"
}

place rocky-8-x86_64 "$site/rpm/8/x86_64"
place rocky-8-aarch64 "$site/rpm/8/aarch64"
place rocky-9-x86_64 "$site/rpm/9/x86_64"
place rocky-9-aarch64 "$site/rpm/9/aarch64"
place rocky-10-x86_64 "$site/rpm/10/x86_64"
place rocky-10-aarch64 "$site/rpm/10/aarch64"
place ubuntu-24.04-amd64 "$site/apt/pool/noble/amd64"
place ubuntu-24.04-arm64 "$site/apt/pool/noble/arm64"
place ubuntu-26.04-amd64 "$site/apt/pool/resolute/amd64"
place ubuntu-26.04-arm64 "$site/apt/pool/resolute/arm64"

big=$(find "$site" -type f -size +100M -print)
if [ -n "$big" ]; then
    echo "ERROR: GitHub Pages rejects files over 100MB:" >&2
    echo "$big" >&2
    exit 1
fi

gnupg_home=$(mktemp -d)
chmod 700 "$gnupg_home"
export GNUPGHOME=$gnupg_home
printf '%s\n' 'allow-loopback-pinentry' > "$gnupg_home/gpg-agent.conf"
printf '%s\n' "$key_text" | gpg --batch --import
keyid=$(gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr:/ { print $10; exit }')
if [ -z "$keyid" ]; then
    echo "ERROR: the repository signing key has no fingerprint." >&2
    exit 1
fi
gpg --batch --export --armor "$keyid" > "$site/elbencho.gpg"

cat > "$HOME/.rpmmacros" <<EOF
%_signature gpg
%_gpg_name ${keyid}
%_gpg_path ${gnupg_home}
%__gpg /usr/bin/gpg
%__gpg_sign_cmd %{__gpg} --batch --no-armor --no-secmem-warning --pinentry-mode loopback -u "%{_gpg_name}" -sbo %{__signature_filename} --digest-algo sha256 %{__plaintext_filename}
EOF

while IFS= read -r rpm; do
    rpmsign --addsign "$rpm"
done < <(find "$site/rpm" -name '*.rpm')

while IFS= read -r dir; do
    createrepo_c "$dir"
done < <(find "$site/rpm" -mindepth 2 -maxdepth 2 -type d)

cat > "$site/elbencho.repo" <<'EOF'
[elbencho]
name=elbencho
baseurl=https://breuner.github.io/elbencho/rpm/$releasever/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://breuner.github.io/elbencho/elbencho.gpg
EOF

sign_apt() {
    local suite=$1
    local arch dir
    for arch in amd64 arm64; do
        dir=$site/apt/dists/${suite}/main/binary-${arch}
        mkdir -p "$dir"
        (
            cd "$site/apt"
            dpkg-scanpackages -m "pool/${suite}/${arch}" /dev/null
        ) > "$dir/Packages"
        gzip -9 -c "$dir/Packages" > "$dir/Packages.gz"
    done
    {
        cat <<EOF
Origin: elbencho
Label: elbencho
Suite: ${suite}
Codename: ${suite}
Architectures: amd64 arm64
Components: main
Description: elbencho
EOF
        (
            cd "$site/apt"
            apt-ftparchive release "dists/${suite}"
        )
    } > "$site/apt/dists/${suite}/Release"
    gpg --batch --yes --pinentry-mode loopback --clearsign \
        --output "$site/apt/dists/${suite}/InRelease" \
        "$site/apt/dists/${suite}/Release"
    gpg --batch --yes --pinentry-mode loopback --detach-sign --armor \
        --output "$site/apt/dists/${suite}/Release.gpg" \
        "$site/apt/dists/${suite}/Release"
}

sign_apt noble
sign_apt resolute

pages=$(mktemp -d)
git init -b gh-pages "$pages"
cp -a "$site"/. "$pages"/
(
    cd "$pages"
    git add -A
    git -c user.name="Sven Breuner" -c user.email="sven.breuner@gmail.com" \
        commit -m "Publish the elbencho package repository for ${tag}."
    git remote add origin https://github.com/breuner/elbencho.git
    git -c http.extraheader="AUTHORIZATION: bearer ${token}" \
        push --force origin HEAD:gh-pages
)

export GH_TOKEN=$token
if gh api repos/breuner/elbencho/pages >/dev/null 2>&1; then
    echo "GitHub Pages is already enabled."
else
    if ! gh api --method POST repos/breuner/elbencho/pages \
        -f build_type=legacy \
        -f source[branch]=gh-pages \
        -f source[path]=/ >/dev/null; then
        echo "WARNING: the release token could not enable GitHub Pages." >&2
        echo "Enable Pages for breuner/elbencho from the gh-pages branch, path /." >&2
    fi
fi

echo "Published https://breuner.github.io/elbencho/ for ${tag}."
rm -rf "$gnupg_home" "$pages"
