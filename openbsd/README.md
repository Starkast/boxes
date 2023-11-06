# OpenBSD

Pointers for building a box for a new OpenBSD version.

# `amd64`

Uses VirtualBox.

1. Verify the checksum of the new ISO [with signify]
1. Update the template file
    1. Update the version
    1. Update the checksum

[with signify]: https://www.openbsd.org/faq/faq4.html#Download

# `arm64`

Uses VMware Fusion.

1. Download miniroot image: `curl -o miniroot.img https://ftp.lysator.liu.se/pub/OpenBSD/7.1/arm64/miniroot71.img`
1. Verify the checksum of the miniroot image [with signify]
1. Convert miniroot image to VMware disk: `qemu-img convert -f raw -O vmdk miniroot.img miniroot.vmdk`
1. Validate box config: `packer validate arm64.pkr.hcl`
1. Build the box: `packer build arm64.pkr.hcl`
