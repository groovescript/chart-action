#!/usr/bin/env bash
set -euo pipefail

version="${LILYPOND_VERSION}"
url="https://gitlab.com/lilypond/lilypond/-/releases/v${version}/downloads/lilypond-${version}-linux-x86_64.tar.gz"

echo "Installing LilyPond ${version} from ${url}"
curl -sSL "$url" | tar -xz -C /opt
mv "/opt/lilypond-${version}" /opt/lilypond
echo "LilyPond ${version} installed at /opt/lilypond"
