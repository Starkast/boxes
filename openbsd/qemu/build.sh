#!/bin/sh
# Build an OpenBSD/arm64 Vagrant *libvirt* box with QEMU/KVM.
#
# Unlike the VirtualBox (amd64) and VMware Fusion (arm64) templates, this runs
# headless on a Linux/KVM host, so it works in CI or on a Linux dev box (incl.
# nested-virt VMs). It boots the miniroot installer, drives an unattended
# install over the serial console (see install.py), provisions over SSH, and
# packages the qcow2 as a libvirt box.
#
# Requirements (Debian/Ubuntu): qemu-system-arm qemu-utils qemu-efi-aarch64
# signify-openbsd signify-openbsd-keys sshpass, and access to /dev/kvm.
set -eu

MAJOR=7
MINOR=8
ARCH=arm64
VERSION="$MAJOR.$MINOR"
MIRROR="https://cdn.openbsd.org"
DISK_GB=20
HTTP_PORT=8000
SSH_PORT=2222

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work="$here/work"
box="$here/openbsd-$VERSION-$ARCH-libvirt.box"
code_fw=/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd
vars_fw=/usr/share/AAVMF/AAVMF_VARS.fd
ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

qmp_vm() { pidfile=$1; [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null || true; }
cleanup() {
  qmp_vm "$work/qemu.pid"
  [ -n "${http_pid:-}" ] && kill "$http_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$work"
cd "$work"

echo "== fetch and verify miniroot =="
miniroot="miniroot$MAJOR$MINOR.img"
base="$MIRROR/pub/OpenBSD/$VERSION/$ARCH"
for f in "$miniroot" SHA256 SHA256.sig; do
  [ -f "$f" ] || curl -fsS -O "$base/$f"
done
pubkey="/usr/share/signify-openbsd-keys/openbsd-$MAJOR$MINOR-base.pub"
if [ -f "$pubkey" ]; then
  signify-openbsd -C -p "$pubkey" -x SHA256.sig "$miniroot"
else
  grep " ($miniroot) " SHA256 | sha256sum -c - 2>/dev/null || \
    { echo "checksum mismatch"; exit 1; }
fi

echo "== prepare disks =="
qemu-img create -f qcow2 disk.qcow2 "${DISK_GB}G" >/dev/null
cp "$vars_fw" vars.fd
chmod +w vars.fd

echo "== serve the autoinstall response file + disklabel =="
srv="$work/srv"
mkdir -p "$srv"
cat > "$srv/install.conf" <<EOF
System hostname = openbsd$MAJOR$MINOR
Which disk is the root disk = sd1
Use (W)hole disk MBR, whole disk (G)PT or (E)dit = whole
URL to autopartitioning template for disklabel = http://10.0.2.2:$HTTP_PORT/disklabel
IPv4 address = autoconf
IPv6 address = none
DNS domain = local
IPv6 default router = none
Password for root = vagrant
Setup a user = vagrant
Password for user = vagrant
Allow root ssh login = yes
What timezone are you in = UTC
Location of sets = http
HTTP Server = ${MIRROR#https://}
Server directory = pub/OpenBSD/$VERSION/$ARCH/
Set name(s) = -game*.tgz -x*.tgz
Continue without verification = yes
EOF
cp "$here/../scripts/openbsd_20G.disklabel" "$srv/disklabel"
python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 --directory "$srv" >http.log 2>&1 &
http_pid=$!

echo "== install (serial-driven autoinstall) =="
# gic-version=3 and virtio INTx (vectors=0) keep the guest from hanging on lost
# interrupts; the chardev logfile keeps the serial console drained. Installer is
# sd0 (bootloader reads /bsd from it); the 20G target is sd1.
run_installer() {
  qemu-system-aarch64 \
    -machine virt,gic-version=3 -accel kvm -cpu host -smp 1 -m 2048 \
    -drive if=pflash,format=raw,readonly=on,file="$code_fw" \
    -drive if=pflash,format=raw,file=vars.fd \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0,vectors=0 \
    -drive if=none,file="$miniroot",format=raw,id=inst \
    -device virtio-blk-pci,drive=inst,vectors=0,bootindex=0 \
    -drive if=none,file=disk.qcow2,format=qcow2,id=tgt \
    -device virtio-blk-pci,drive=tgt,vectors=0 \
    -chardev socket,id=s0,path=serial.sock,server=on,wait=off,logfile=serial.log \
    -serial chardev:s0 -display none -daemonize -pidfile qemu.pid
}
rm -f serial.sock serial.log qemu.pid
run_installer
python3 "$here/install.py" serial.sock serial.log
qmp_vm qemu.pid

echo "== provision (boot installed disk, run scripts over SSH) =="
cp "$vars_fw" vars-prov.fd
chmod +w vars-prov.fd
rm -f serial-prov.log qemu.pid
qemu-system-aarch64 \
  -machine virt,gic-version=3 -accel kvm -cpu host -smp 1 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file="$code_fw" \
  -drive if=pflash,format=raw,file=vars-prov.fd \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22 \
  -device virtio-net-pci,netdev=net0,vectors=0 \
  -drive if=none,file=disk.qcow2,format=qcow2,id=d0 \
  -device virtio-blk-pci,drive=d0,vectors=0,bootindex=0 \
  -chardev socket,id=s0,path=serial-prov.sock,server=on,wait=off,logfile=serial-prov.log \
  -serial chardev:s0 -display none -daemonize -pidfile qemu.pid

echo "waiting for sshd ..."
i=0
until sshpass -p vagrant ssh $ssh_opts -p "$SSH_PORT" root@127.0.0.1 true 2>/dev/null; do
  i=$((i + 1)); [ "$i" -gt 60 ] && { echo "sshd timeout"; exit 1; }
done
for s in postinstall.sh vagrant.sh minimize.sh; do
  echo "-- $s --"
  sshpass -p vagrant ssh $ssh_opts -p "$SSH_PORT" root@127.0.0.1 'sh -es' < "$here/../scripts/$s"
done
sshpass -p vagrant ssh $ssh_opts -p "$SSH_PORT" root@127.0.0.1 'halt -p' 2>/dev/null || true
i=0; while kill -0 "$(cat qemu.pid 2>/dev/null)" 2>/dev/null; do i=$((i + 1)); [ "$i" -gt 60 ] && break; done

echo "== package the libvirt box =="
pkg="$work/pkg"
rm -rf "$pkg"; mkdir -p "$pkg"
qemu-img convert -c -O qcow2 disk.qcow2 "$pkg/box.img"
printf '{\n  "provider": "libvirt",\n  "format": "qcow2",\n  "virtual_size": %d\n}\n' "$DISK_GB" > "$pkg/metadata.json"
cp "$here/Vagrantfile.template" "$pkg/Vagrantfile"
tar -C "$pkg" -czf "$box" ./metadata.json ./Vagrantfile ./box.img
echo "built $box"
