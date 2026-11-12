<p align="center">
  <a href="https://openimages.cloud/images/freebsd-15/">
    <img src="https://openimages.cloud/img/og/freebsd-15.png" alt="FreeBSD cloud images for OpenStack and Proxmox" width="720">
  </a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/freebsd-15/"><img alt="FreeBSD 15 latest version" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fimages.openimages.cloud%2Ffreebsd-15%2Flatest%2FMANIFEST.json&query=%24.version&label=FreeBSD%2015&color=2459c4&cacheSeconds=3600"></a>
  <a href="https://openimages.cloud/images/freebsd-14/"><img alt="FreeBSD 14 latest version" src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fimages.openimages.cloud%2Ffreebsd-14%2Flatest%2FMANIFEST.json&query=%24.version&label=FreeBSD%2014&color=2459c4&cacheSeconds=3600"></a>
  <a href="https://github.com/open-img-cloud/freebsd/actions/workflows/release.yml"><img alt="Release" src="https://github.com/open-img-cloud/freebsd/actions/workflows/release.yml/badge.svg"></a>
  <a href="https://openimages.cloud/verify/"><img alt="Signed with Sigstore cosign" src="https://img.shields.io/badge/signed-Sigstore%20cosign-2459c4"></a>
  <a href="https://openimages.cloud/quality/"><img alt="Boot-tested on OpenStack" src="https://img.shields.io/badge/boot--tested-OpenStack-2459c4"></a>
  <a href="LICENSE.md"><img alt="License GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-555"></a>
</p>

<p align="center">
  <a href="https://openimages.cloud/images/freebsd-15/"><b>FreeBSD 15</b></a> ·
  <a href="https://openimages.cloud/images/freebsd-14/"><b>FreeBSD 14</b></a> ·
  <a href="https://images.openimages.cloud/freebsd-15/latest/">Download 15</a> ·
  <a href="https://images.openimages.cloud/freebsd-14/latest/">Download 14</a> ·
  <a href="https://openimages.cloud/verify/">Verify</a> ·
  <a href="https://github.com/open-img-cloud/docs">Documentation</a> ·
  <a href="https://github.com/open-img-cloud/freebsd/issues">Report an issue</a>
</p>

FreeBSD 15 and FreeBSD 14 cloud images (qcow2) for **OpenStack** and **Proxmox**: FreeBSD ships
no OpenStack image with cloud-init, so these are built from the official release distribution
sets on a ZFS root, made ready for both clouds with the same rules as every
[openimages.cloud](https://openimages.cloud) image, signed with Sigstore cosign and boot-tested
on a real OpenStack before they are published.

## At a glance

| | |
|---|---|
| **Upstream** | [FreeBSD](https://www.freebsd.org/) release sets `base.txz` and `kernel.txz` from [download.freebsd.org](https://download.freebsd.org/releases/amd64/), checked against the release `MANIFEST`, then patched with `freebsd-update` |
| **Catalog ids** | `freebsd-15` (current branch, follows [`VERSION`](VERSION)) and `freebsd-14` (14.5, the last 14.x release) |
| **Default user** | `freebsd`, SSH key only, passwordless `sudo`, login shell `/bin/sh` |
| **Firmware** | BIOS and UEFI (the same image boots both) |
| **Format** | qcow2, x86_64, ZFS root (pool `zroot`) grown to the disk at first boot |
| **Version** | FreeBSD release, `<major>.<minor>`, e.g. `15.1` ([15 versions](https://images.openimages.cloud/freebsd-15/versions.json), [14 versions](https://images.openimages.cloud/freebsd-14/versions.json)) |
| **Support** | FreeBSD 15 until 2029-12-31, FreeBSD 14 until 2028-11-30 ([FreeBSD security page](https://www.freebsd.org/security/)); prefer 15 for new deployments |

## Quick start

```sh
# Pick the branch: freebsd-15 or freebsd-14
ID=freebsd-15
# Latest version and its file name, from the signed manifest
M=https://images.openimages.cloud/$ID/latest/MANIFEST.json
V=$(curl -fsS $M | jq -r .version); F=$(curl -fsS $M | jq -r .filename)
curl -fLO https://images.openimages.cloud/$ID/$V/$F
```

<details>
<summary><b>OpenStack</b></summary>

```sh
openstack image create --disk-format qcow2 --container-format bare \
  --property os_distro=freebsd --property os_version=$V \
  --property hw_qemu_guest_agent=yes --property os_require_quiesce=no \
  --property os_admin_user=freebsd \
  --file "$F" "FreeBSD $V"
```

`os_require_quiesce=no`: the FreeBSD guest agent can only freeze UFS, not ZFS, so snapshots
are taken without quiescing. The full property set is on the catalog pages
([15](https://openimages.cloud/images/freebsd-15/), [14](https://openimages.cloud/images/freebsd-14/))
and in [`index.json`](https://images.openimages.cloud/index.json). To keep images up to date
automatically, use [oic-sync](https://github.com/open-img-cloud/oic-sync).

</details>

<details>
<summary><b>Proxmox VE</b></summary>

The commands to create a cloud-init template from these images are on the catalog pages
([15](https://openimages.cloud/images/freebsd-15/), [14](https://openimages.cloud/images/freebsd-14/)).

</details>

<details>
<summary><b>Verify the signature</b></summary>

```sh
curl -fLO https://images.openimages.cloud/$ID/$V/$F.bundle
cosign verify-blob "$F" --bundle "$F.bundle" \
  --certificate-identity-regexp '^https://github.com/open-img-cloud/\.github/\.github/workflows/build-(libguestfs|dib|nix-flake|freebsd)-image\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

</details>

## What this image contains

[`build/build.sh`](build/build.sh) runs in an ephemeral FreeBSD virtual machine and builds the
image from scratch:

- GPT disk with BIOS (`gptzfsboot`) and UEFI (`loader.efi`) boot code, ZFS root pool `zroot`
  with `autoexpand`; cloud-init grows the partition and the pool at first boot;
- the release sets with the latest security patches (`freebsd-update`);
- `net/cloud-init` with the openimages.cloud policy: config drive read first, then the
  metadata service; no root login, no SSH password; the `freebsd` user logs in with `/bin/sh`
  instead of `tcsh`, so commands sent over SSH behave as on the Linux images;
- `dhcpcd` on every interface: DHCPv4, and IPv6 with the address Neutron assigns to the port
  (`slaac hwaddr`); cloud-init does not render the network;
- sshd with public keys only, root password locked, `qemu-guest-agent`, `sudo`, serial
  console on `ttyu0`;
- host keys, `hostid`, `resolv.conf` and caches removed so every instance starts fresh.

Every release must pass the same [runtime contract](https://openimages.cloud/quality/) on
OpenStack: SSH with the injected key, cloud-init finished, DNS, hostname, root filesystem grown,
passwordless `sudo`, IPv6 address and egress.

## How releases happen

1. Every day at 07:14 UTC a watcher looks for a new FreeBSD 15.x release and opens a pull
   request that bumps [`VERSION`](VERSION).
2. Merging it is all it takes: the release is tagged, then both images are built, signed,
   boot-tested and published (FreeBSD 15 from `VERSION`, FreeBSD 14 at the 14.5 set in
   [`release.yml`](.github/workflows/release.yml)), and `latest/` and the
   [catalog](https://openimages.cloud/images/) move to them.

This repository only holds what is specific to FreeBSD: [`VERSION`](VERSION),
[`build/build.sh`](build/build.sh), [`build/detect-upstream.sh`](build/detect-upstream.sh)
and thin workflows calling the shared pipeline in
[`open-img-cloud/.github`](https://github.com/open-img-cloud/.github).

## License

The build tooling in this repository is under [GPL-3.0](LICENSE.md); `build/build.sh` derives
from [linitio/openstack-freebsd-image](https://github.com/linitio/openstack-freebsd-image),
released under the same license. The image keeps the licensing terms of FreeBSD (BSD licenses)
and of the packages it installs. FreeBSD is a registered trademark of The FreeBSD Foundation;
this project is not affiliated with it.
