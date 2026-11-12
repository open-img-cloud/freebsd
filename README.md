# FreeBSD cloud images

Cloud-init-ready, signed FreeBSD 15 and FreeBSD 14 qcow2 images for OpenStack
and Proxmox, part of the [openimages.cloud](https://openimages.cloud) catalog.

- Catalog pages: <https://openimages.cloud/images/freebsd-15/>,
  <https://openimages.cloud/images/freebsd-14/>
- Registry: <https://images.openimages.cloud/freebsd-15/latest/>,
  <https://images.openimages.cloud/freebsd-14/latest/>

## About

FreeBSD is an operating system published by the FreeBSD Project
([https://www.freebsd.org/](https://www.freebsd.org/)). FreeBSD ships no
official OpenStack image with cloud-init, so this repo builds one from the
release distribution sets: `build/build.sh` downloads `base.txz` and
`kernel.txz`, verifies them against the release `MANIFEST`, installs them on
a ZFS root, applies the security patches (`freebsd-update`) and configures
the image for the cloud. The image is then boot-tested on OpenStack, signed
with cosign (keyless) and published.

The build runs in an ephemeral FreeBSD virtual machine through the
[`build-freebsd-image.yml`](https://github.com/open-img-cloud/.github/blob/main/.github/workflows/build-freebsd-image.yml)
reusable workflow of [`open-img-cloud/.github`](https://github.com/open-img-cloud/.github).
This repo only ships `VERSION`, `build/build.sh`, `build/detect-upstream.sh`
and two thin caller workflows.

## Lifecycle

| Branch | Bucket | Release | Supported until |
|---|---|---|---|
| FreeBSD 15 | `freebsd-15` | follows `VERSION` (watched daily) | 2029-12-31 |
| FreeBSD 14 | `freebsd-14` | 14.5, the last 14.x release | 2028-11-30 |

FreeBSD 15 is the current production branch; prefer it for new deployments.
Dates come from the [FreeBSD security page](https://www.freebsd.org/security/).

## Image

- File: `freebsd-<version>-x86_64.qcow2` (e.g. `freebsd-14.5-x86_64.qcow2`),
  6 GiB virtual disk, BIOS and UEFI boot.
- Default user: `freebsd` (SSH key from cloud-init, passwordless sudo). Its
  login shell is `sh`.
- ZFS root (pool `zroot`): the partition and the pool grow to the flavor
  disk on first boot.
- `net/cloud-init` with the ConfigDrive and OpenStack datasources (SSH key,
  hostname, user data).
- Network: `dhcpcd` on every interface, DHCPv4 and IPv6 with the address
  Neutron assigns to the port (`slaac hwaddr`).
- sshd accepts public keys only, root login is disabled and the root
  password is locked. Serial console on `ttyu0`, `qemu-guest-agent` enabled.

## Use it

```sh
V=14.5
curl -fLO https://images.openimages.cloud/freebsd-14/$V/freebsd-$V-x86_64.qcow2

openstack image create \
    --disk-format qcow2 --container-format bare \
    --property os_distro=freebsd --property os_version=$V \
    --property hw_qemu_guest_agent=yes \
    --file freebsd-$V-x86_64.qcow2 \
    'FreeBSD '$V
```

Verification (cosign), Proxmox commands and provenance details are on the
catalog pages and in the [verification guide](https://openimages.cloud/verify/).

## Release flow

1. `watch.yml` runs daily and opens an `auto/upstream-bump` pull request on
   `VERSION` when a new FreeBSD 15.x release is published.
2. Merge it, then push the tag `v<VERSION>`: `release.yml` builds FreeBSD 15
   (from `VERSION`) and FreeBSD 14 (14.5, set in the workflow), boot-tests,
   signs and publishes both images.

## License

The build tooling in this repository is [GPL-3.0](LICENSE.md). `build/build.sh`
derives from [linitio/openstack-freebsd-image](https://github.com/linitio/openstack-freebsd-image),
released under the same license. The image keeps the licensing terms of
FreeBSD (BSD licenses) and of the packages it installs. FreeBSD is a
registered trademark of The FreeBSD Foundation; this project is not
affiliated with it.
