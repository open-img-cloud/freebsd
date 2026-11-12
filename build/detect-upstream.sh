#!/usr/bin/env bash
# Prints the latest FreeBSD 15.x release (e.g. 15.1) whose distribution
# sets are published. Runs in the upstream-watch reusable workflow.
set -euo pipefail
URL='https://download.freebsd.org/releases/amd64/'
listing=$(curl -fsL "$URL")
for v in $(printf '%s\n' "$listing" | grep -oE '15\.[0-9]+-RELEASE' | sed 's/-RELEASE//' | sort -uVr); do
  if curl -fsIL -o /dev/null "${URL}${v}-RELEASE/base.txz"; then
    printf '%s\n' "$v"
    exit 0
  fi
done
echo "::error::no FreeBSD 15.x release found in $URL" >&2
exit 1
