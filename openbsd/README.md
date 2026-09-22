# OpenBSD

Pointers for building a box for a new OpenBSD version.

# VirtualBox

Used to build `amd64` boxes.

1. Verify the checksum of the new ISO [with signify]
1. Update the template file
    1. Update the version
    1. Update the checksum

[with signify]: https://www.openbsd.org/faq/faq4.html#Download

# VMware Fusion

Used to build `arm64` boxes.

1. Download miniroot image: `curl -O https://cdn.openbsd.org/pub/OpenBSD/7.9/arm64/miniroot.img`
1. Verify the checksum of the miniroot image [with signify]
1. Convert miniroot image to VMware disk: `qemu-img convert -f raw -O vmdk miniroot79.img vmware-vmx/miniroot.vmdk`
1. Validate box config: `packer validate vmware-vmx.pkr.hcl`
1. Build the box: `packer build vmware-vmx.pkr.hcl`

An interrupted build leaves the half-installed VM behind in `packer_cache/`,
and the next build boots that disk instead of installing from the miniroot.
Remove the directory before building again.

If packer waits for SSH forever although the VM is up, macOS Local Network
privacy is blocking the (ad-hoc signed) vmware plugin from reaching the guest.
Relay SSH through localhost with an Apple-signed tool instead:

    mkfifo /tmp/relay
    while true; do nc -l 127.0.0.1 22079 < /tmp/relay | nc <guest ip> 22 > /tmp/relay; done
    packer build -var ssh_host=127.0.0.1 -var ssh_port=22079 vmware-vmx.pkr.hcl

The guest IP is in `/var/db/vmware/vmnet-dhcpd-vmnet8.leases`.
