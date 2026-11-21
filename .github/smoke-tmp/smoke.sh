#!/bin/bash
# usage: smoke.sh <image.qcow2> <bios|uefi> <tag>   (runs inside the qemu container, /w = workdir)
W=${W:-/w}
set -u
img=$1; fw=$2; tag=$3; cd "$W"
rm -f key key.pub; ssh-keygen -q -t ed25519 -N '' -f key
mkdir -p seed-$tag; cat > seed-$tag/meta-data <<M
instance-id: oic-smoke-$tag
local-hostname: oic-smoke-$tag
M
cat > seed-$tag/user-data <<U
#cloud-config
ssh_authorized_keys:
  - $(cat key.pub)
U
genisoimage -quiet -output seed-$tag.iso -volid cidata -joliet -rock seed-$tag/user-data seed-$tag/meta-data
qemu-img create -q -f qcow2 -F qcow2 -b "$img" disk-$tag.qcow2 12G
fwargs=(); if [ "$fw" = uefi ]; then cp /usr/share/OVMF/OVMF_VARS_4M.fd vars-$tag.fd
  fwargs=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,file=vars-$tag.fd); fi
qemu-system-x86_64 -accel kvm -cpu host -smp 2 -m 1536 -nographic "${fwargs[@]}" \
  -drive file=disk-$tag.qcow2,if=virtio -drive file=seed-$tag.iso,media=cdrom \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0 \
  -chardev socket,path=$W/qga-$tag.sock,server=on,wait=off,id=qga0 -device virtio-serial -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
  -serial file:console-$tag.log -monitor none -display none &
qpid=$!
t0=$(date +%s); ok=0
o="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR -i key -p 2222"
while [ $(( $(date +%s) - t0 )) -lt 900 ]; do
  ssh $o freebsd@127.0.0.1 true 2>/dev/null && { ok=1; break; }; sleep 5
done
echo "[$tag] ssh: $([ $ok = 1 ] && echo OK || echo FAIL) after $(( $(date +%s) - t0 ))s"
if [ $ok = 1 ]; then
  ssh $o freebsd@127.0.0.1 'echo "version: $(freebsd-version -ku | tr "\n" " ")"; echo "hostname: $(hostname)"; echo "pool: $(zpool list -H -o name,size,health | tr "\t" " ")"; echo "root fs: $(df -h / | tail -1 | awk "{print \$2}")"; echo "qga service: $(service qemu-guest-agent status 2>&1)"; echo "cloud-init: $(cloud-init status --long 2>&1 | tr "\n" " ")"; echo "sudo: $(sudo -n true && echo OK || echo FAIL)"; echo "shell: $SHELL"'
  echo "qga ping: $(printf '{"execute":"guest-ping"}\n' | timeout 10 socat - UNIX-CONNECT:$W/qga-$tag.sock)"
fi
kill $qpid 2>/dev/null; wait $qpid 2>/dev/null
rm -f disk-$tag.qcow2
