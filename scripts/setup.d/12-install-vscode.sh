#!/usr/bin/env bash

set -euo pipefail

/tmp/cached-curl.sh "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" \
    /tmp/code.deb

apt-get install -y /tmp/code.deb || {
    apt-get -f install -y
    apt-get install -y /tmp/code.deb
}

rm -f /tmp/code.deb
