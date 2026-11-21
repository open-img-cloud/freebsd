#!/usr/bin/env bash
# Prints the latest FreeBSD 15.x release with its security patch level:
# 15.1-p7, or 15.2 before its first patch. Runs in the upstream-watch reusable
# workflow; a new patch level opens a release PR like a new point release.
#
# Release: newest 15.x whose distribution sets are published.
# Patch level: the freebsd-update metadata of that release (latest.ssl), the
# same source freebsd-update reads, verified with the FreeBSD update key
# (KeyPrint of /etc/freebsd-update.conf). Served over HTTP like freebsd-update
# itself does; the signature is what is trusted.
set -euo pipefail
MAJOR=15
KEYPRINT=800651ef4b4c71c27e60786d7b487188970f4b4169cc055784e21eb71d410cc5
DIST='https://download.freebsd.org/releases/amd64/'
UPDATE='http://update.freebsd.org'
UA='openimages.cloud-watch'

release=
listing=$(curl -fsL -A "$UA" "$DIST")
for v in $(printf '%s\n' "$listing" | grep -oE "${MAJOR}\.[0-9]+-RELEASE" | sed 's/-RELEASE//' | sort -uVr); do
  if curl -fsIL -A "$UA" -o /dev/null "${DIST}${v}-RELEASE/base.txz"; then
    release=$v
    break
  fi
done
if [[ -z "$release" ]]; then
  echo "::error::no FreeBSD ${MAJOR}.x release found in $DIST" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base="${UPDATE}/${release}-RELEASE/amd64"
if ! curl -fsL -A "$UA" -o "$tmp/pub.ssl" "$base/pub.ssl" \
   || ! curl -fsL -A "$UA" -o "$tmp/latest.ssl" "$base/latest.ssl"; then
  # No update metadata yet (release just out): no patch level.
  echo "::warning::no freebsd-update metadata for ${release}-RELEASE: reporting the release alone" >&2
  printf '%s\n' "$release"
  exit 0
fi
if [[ "$(sha256sum "$tmp/pub.ssl" | cut -c1-64)" != "$KEYPRINT" ]]; then
  echo "::error::freebsd-update key of ${release}-RELEASE does not match the FreeBSD KeyPrint" >&2
  exit 1
fi
# freebsd-update|amd64|15.1-RELEASE|7|<sha256 of tag>|<EOL timestamp>
tag=$(openssl pkeyutl -verifyrecover -pubin -inkey "$tmp/pub.ssl" -in "$tmp/latest.ssl")
IFS='|' read -r magic arch rel patch _ <<<"$tag"
if [[ "$magic" != freebsd-update || "$arch" != amd64 || "$rel" != "${release}-RELEASE" || ! "$patch" =~ ^[0-9]+$ ]]; then
  echo "::error::unexpected freebsd-update tag for ${release}-RELEASE: $tag" >&2
  exit 1
fi
if [[ "$patch" -eq 0 ]]; then
  printf '%s\n' "$release"
else
  printf '%s\n' "${release}-p${patch}"
fi
