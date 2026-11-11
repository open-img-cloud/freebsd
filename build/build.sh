#!/bin/sh
# Builds a FreeBSD cloud image for OpenStack and Proxmox.
#
# Runs as root on a FreeBSD host (the build-freebsd-image reusable workflow
# boots an ephemeral FreeBSD VM for it):  sh build/build.sh <version> <out-dir>
# Produces <out-dir>/image.raw.
#
# Image contract (checked by the OpenStack runtime smoke in strict mode):
#   - cloud-init (net/cloud-init) with the ConfigDrive and OpenStack
#     datasources: SSH key, hostname, `freebsd` default user with
#     passwordless sudo, root partition and ZFS pool grown to the disk;
#   - IPv4 (DHCP) and IPv6 (SLAAC, EUI-64 address as assigned by Neutron)
#     through dhcpcd on every interface; cloud-init does not render the
#     network;
#   - sshd: public key only, root login disabled, root password locked;
#   - serial console, qemu-guest-agent, BIOS and UEFI boot.
#
# Derived from linitio/openstack-freebsd-image (GPL-3.0).

set -eu

VERSION="${1:?usage: build.sh <version> <out-dir>}"
OUT="${2:?usage: build.sh <version> <out-dir>}"
SIZE="${IMAGE_SIZE:-6G}"
POOL=zroot
TMPPOOL=oicbuild

DIST="https://download.freebsd.org/releases/amd64/${VERSION}-RELEASE"
work=$(mktemp -d /tmp/oic.XXXXXX)
mnt="$work/mnt"
mkdir -p "$OUT" "$mnt"
img="$OUT/image.raw"

echo "[build] FreeBSD $VERSION, $SIZE, ZFS root"

# --- Distribution sets, verified against the release MANIFEST -------------
fetch -o "$work/MANIFEST" "$DIST/MANIFEST"
for set in base kernel; do
  fetch -o "$work/$set.txz" "$DIST/$set.txz"
  want=$(awk -v f="$set.txz" '$1 == f {print $2}' "$work/MANIFEST")
  got=$(sha256 -q "$work/$set.txz")
  if [ -z "$want" ] || [ "$want" != "$got" ]; then
    echo "::error::$set.txz checksum mismatch (want $want, got $got)" >&2
    exit 1
  fi
  echo "[build] $set.txz sha256 verified"
done

# --- Disk: GPT, BIOS boot + EFI, ZFS root last (growpart extends it) -----
rm -f "$img"
truncate -s "$SIZE" "$img"
md=$(mdconfig -a -t vnode -f "$img")
cleanup() {
  set +e
  umount "$mnt/dev" 2>/dev/null
  zpool export "$TMPPOOL" 2>/dev/null
  umount "$work/efi" 2>/dev/null
  mdconfig -d -u "$md" 2>/dev/null
}
trap cleanup EXIT

gpart create -s gpt "$md"
gpart add -t freebsd-boot -s 512k -l gptboot "$md"
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 "$md"
gpart add -t efi -s 64M -l efiboot "$md"
gpart add -t freebsd-zfs -l rootfs "$md"

newfs_msdos -F 32 -c 1 "/dev/${md}p2"
mkdir -p "$work/efi"
mount -t msdosfs "/dev/${md}p2" "$work/efi"
mkdir -p "$work/efi/EFI/BOOT" "$work/efi/EFI/freebsd"

# Pool named zroot in the image, imported here under a temporary name.
zpool create -f -o altroot="$mnt" -o cachefile=none -o autoexpand=on -t "$TMPPOOL" \
  -O compression=lz4 -O atime=off -O mountpoint=none "$POOL" "/dev/${md}p3"
zfs create -o mountpoint=none "$TMPPOOL/ROOT"
zfs create -o mountpoint=/ -o canmount=noauto "$TMPPOOL/ROOT/default"
zfs mount "$TMPPOOL/ROOT/default"
for ds in tmp:exec=on,setuid=off var:canmount=off var/log:exec=off,setuid=off var/tmp:setuid=off home:; do
  name=${ds%%:*}; props=${ds#*:}
  opts="-o mountpoint=/$name"
  [ -n "$props" ] && for p in $(echo "$props" | tr ',' ' '); do opts="$opts -o $p"; done
  # shellcheck disable=SC2086
  zfs create $opts "$TMPPOOL/$name"
done
zpool set bootfs="$TMPPOOL/ROOT/default" "$TMPPOOL"

tar -xpf "$work/base.txz" -C "$mnt"
tar -xpf "$work/kernel.txz" -C "$mnt"
cp "$mnt/boot/loader.efi" "$work/efi/EFI/BOOT/BOOTX64.EFI"
cp "$mnt/boot/loader.efi" "$work/efi/EFI/freebsd/loader.efi"
umount "$work/efi"

# --- Configuration inside the image --------------------------------------
cp /etc/resolv.conf "$mnt/etc/resolv.conf"
mount -t devfs devfs "$mnt/dev"

cat > "$mnt/tmp/oic-setup.sh" <<'SETUP'
#!/bin/sh
set -eu
export ASSUME_ALWAYS_YES=yes PAGER=cat

# Security patches for this release.
freebsd-update --not-running-from-cron --currently-running "$(freebsd-version -u | sed 's/-p[0-9]*$//')" fetch || true
freebsd-update --not-running-from-cron --currently-running "$(freebsd-version -u | sed 's/-p[0-9]*$//')" install || true

pkg bootstrap -f
pkg update -f
pkg install -y ca_root_nss sudo dhcpcd qemu-guest-agent net/cloud-init
pkg clean -ay

# dhcpcd: DHCPv4 + SLAAC with the EUI-64 address Neutron assigns to the
# port (the default "slaac private" would pick another address).
sed -i '' -e 's/^slaac private/#slaac private/' /usr/local/etc/dhcpcd.conf
cat >> /usr/local/etc/dhcpcd.conf <<'DHCPCD'

# openimages.cloud
slaac hwaddr
DHCPCD

# sshd: public key only.
cat >> /etc/ssh/sshd_config <<'SSHD'

# openimages.cloud
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
UseDNS no
SSHD

# cloud-init policy (same intent as the catalog drop-in for Linux images).
mkdir -p /usr/local/etc/cloud/cloud.cfg.d
cat > /usr/local/etc/cloud/cloud.cfg.d/99_oic-policy.cfg <<'CI'
# openimages.cloud policy
datasource_list: [ConfigDrive, OpenStack, NoCloud, None]
disable_root: true
ssh_pwauth: false
# dhcpcd brings up IPv4 and IPv6 on every interface.
network: {config: disabled}
growpart:
  mode: auto
  devices: ['/']
resize_rootfs: true
CI

pw usermod root -h -
SETUP
chmod +x "$mnt/tmp/oic-setup.sh"
chroot "$mnt" /tmp/oic-setup.sh
rm -f "$mnt/tmp/oic-setup.sh"

cat >> "$mnt/etc/rc.conf" <<'RC'
hostname="freebsd"
zfs_enable="YES"
# IPv6 is disabled on interfaces without an ifconfig_*_ipv6 line otherwise.
ipv6_activate_all_interfaces="YES"
dhcpcd_enable="YES"
dhcpcd_flags="-q"
sshd_enable="YES"
cloudinit_enable="YES"
qemu_guest_agent_enable="YES"
sendmail_enable="NONE"
clear_tmp_enable="YES"
syslogd_flags="-ss"
dumpdev="NO"
RC

cat >> "$mnt/boot/loader.conf" <<'LOADER'
zfs_load="YES"
vfs.root.mountfrom="zfs:zroot/ROOT/default"
autoboot_delay="2"
beastie_disable="YES"
boot_multicons="YES"
console="comconsole,vidconsole"
comconsole_speed="115200"
LOADER

: > "$mnt/etc/fstab"
umount "$mnt/dev"
rm -f "$mnt/etc/resolv.conf" "$mnt/etc/hostid" "$mnt/etc/ssh/ssh_host_"*
rm -rf "$mnt/var/db/freebsd-update/"* "$mnt/tmp/"* "$mnt/var/tmp/"*

zpool export "$TMPPOOL"
mdconfig -d -u "$md"
trap - EXIT
rm -rf "$work"
echo "[build] done: $img"
