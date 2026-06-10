#!/usr/bin/env bash

set -euo pipefail

truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
