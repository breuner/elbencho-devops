#!/bin/bash
#
# SPDX-FileCopyrightText: 2026 Sven Breuner <sven.breuner@gmail.com>
# SPDX-License-Identifier: GPL-3.0-only
#
# Build the elbencho package repository site from the packages in the artifact
# directory. The site contains only this build. The workflow uploads it with
# actions/upload-pages-artifact and deploys it with actions/deploy-pages.

set -euo pipefail

artifacts=${1:?artifact directory is required}
output=${2:?output directory is required}
tag=${TAG:?TAG is required}
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
baseurl=https://breuner.github.io/elbencho-devops/rpm/$releasever/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://breuner.github.io/elbencho-devops/elbencho.gpg
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

write_listing() {
    local dir=$1 heading=$2
    local base
    {
        cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${heading}</title>
<style>
  body { font-family: sans-serif; line-height: 1.5; max-width: 64rem; margin: 2rem auto; padding: 0 1rem; }
  li { margin: 0.3rem 0; }
</style>
</head>
<body>
<p><a href="../">Back</a></p>
<h1>${heading}</h1>
<ul>
EOF
        local sub
        for sub in "$dir"/*/; do
            [ -d "$sub" ] || continue
            base=$(basename "$sub")
            [ "$base" = repodata ] && continue
            printf '<li><a href="%s/">%s/</a></li>\n' "$base" "$base"
        done
        local file
        shopt -s nullglob
        for file in "$dir"/*.rpm "$dir"/*.deb; do
            base=$(basename "$file")
            printf '<li><a href="%s">%s</a></li>\n' "$base" "$base"
        done
        shopt -u nullglob
        printf '%s\n' '</ul>' '</body>' '</html>'
    } > "$dir/index.html"
}

write_listing "$site/rpm" "rpm packages"
write_listing "$site/rpm/8" "RHEL 8"
write_listing "$site/rpm/8/x86_64" "RHEL 8 x86_64"
write_listing "$site/rpm/8/aarch64" "RHEL 8 aarch64"
write_listing "$site/rpm/9" "RHEL 9"
write_listing "$site/rpm/9/x86_64" "RHEL 9 x86_64"
write_listing "$site/rpm/9/aarch64" "RHEL 9 aarch64"
write_listing "$site/rpm/10" "RHEL 10"
write_listing "$site/rpm/10/x86_64" "RHEL 10 x86_64"
write_listing "$site/rpm/10/aarch64" "RHEL 10 aarch64"
mkdir -p "$site/apt"
write_listing "$site/apt/pool" "deb packages"
write_listing "$site/apt/pool/noble" "Ubuntu 24.04 (noble)"
write_listing "$site/apt/pool/noble/amd64" "Ubuntu 24.04 amd64"
write_listing "$site/apt/pool/noble/arm64" "Ubuntu 24.04 arm64"
write_listing "$site/apt/pool/resolute" "Ubuntu 26.04 (resolute)"
write_listing "$site/apt/pool/resolute/amd64" "Ubuntu 26.04 amd64"
write_listing "$site/apt/pool/resolute/arm64" "Ubuntu 26.04 arm64"
# The apt root has metadata next to the pool. List only the downloadable packages.
cat > "$site/apt/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>deb packages</title>
<style>
  body { font-family: sans-serif; line-height: 1.5; max-width: 64rem; margin: 2rem auto; padding: 0 1rem; }
</style>
</head>
<body>
<p><a href="../">Back</a></p>
<h1>deb packages</h1>
<ul>
<li><a href="pool/">pool/</a></li>
</ul>
</body>
</html>
EOF

cp "$(dirname "$0")/repo-index.html" "$site/index.html"

mkdir -p "$output"
rm -rf "${output:?}/"*
cp -a "$site"/. "$output"/
echo "Prepared the package repository for ${tag} in ${output}."
rm -rf "$gnupg_home"
