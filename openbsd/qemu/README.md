# OpenBSD arm64 libvirt box (QEMU/KVM)

Builds an OpenBSD/arm64 Vagrant **libvirt** box headlessly with QEMU/KVM, so it
works on any Linux host with KVM — CI, a Linux dev box, or a nested-virt VM —
without VMware Fusion or VirtualBox.

The [VirtualBox](../README.md) (amd64) and [VMware Fusion](../README.md) (arm64)
templates need a desktop hypervisor; this one does not.

## Build

On a Debian/Ubuntu host with access to `/dev/kvm`:

    sudo apt-get install -y qemu-system-arm qemu-utils qemu-efi-aarch64 \
        signify-openbsd signify-openbsd-keys sshpass
    # your user needs the kvm group (log out/in after adding):
    sudo usermod -aG kvm "$USER"

    ./build.sh

It produces `openbsd-<version>-arm64-libvirt.box`. Add it and boot a VM with any
Vagrantfile that selects the libvirt provider:

    vagrant box add --name starkast/openbsd-7.8 openbsd-7.8-arm64-libvirt.box
    vagrant up --provider=libvirt

## How it works

`build.sh` runs four stages in `work/`:

1. **Fetch** and signify-verify the miniroot installer image.
2. **Install** — boots the installer and drives an unattended install over the
   serial console (`install.py`) using an autoinstall response file served over
   HTTP. The installer disk is `sd0`; the 20G target is `sd1`.
3. **Provision** — boots the installed disk and runs the shared
   [`../scripts`](../scripts) (`postinstall.sh`, `vagrant.sh`, `minimize.sh`)
   over SSH.
4. **Package** — compresses the qcow2 and tars it into the `.box`.

## QEMU tuning (important)

OpenBSD/arm64 under (nested) KVM needs a few non-obvious settings, all applied
by `build.sh` and mirrored in the ansible `Vagrantfile`'s libvirt provider:

- `-machine virt,gic-version=3` — `gic-version=max` (GICv4/ITS) hangs the guest.
- `-smp 1` — under nested KVM the vGIC drops inter-processor interrupts and an
  SMP guest spins/hangs.
- virtio `vectors=0` (legacy INTx) — nested KVM loses virtio MSI-X interrupts.
- serial console drained to a file/logfile — OpenBSD busy-waits on a full pl011
  TX FIFO, so an undrained console (e.g. an idle pty) hangs the guest.
- no framebuffer/graphics — OpenBSD/arm64 hangs on a framebuffer console; it
  must use the serial console.

## New OpenBSD version

Edit `MAJOR`/`MINOR` at the top of `build.sh`. The response file and disklabel
are generated from those.
