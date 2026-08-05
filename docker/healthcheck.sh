#!/bin/bash
set -euo pipefail

PORT="${VS_PORT:-42420}"

# Fail closed if nothing is listening on the game port.
exec 3<>"/dev/tcp/127.0.0.1/${PORT}"
exec 3<&-
exec 3>&-
exit 0
