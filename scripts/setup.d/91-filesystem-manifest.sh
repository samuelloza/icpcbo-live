#!/usr/bin/env bash

set -euo pipefail

dpkg-query -W --showformat='${Package} ${Version}\n' > /filesystem.manifest
