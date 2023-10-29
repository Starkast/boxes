packer {
  required_plugins {
    vagrant = {
      source  = "github.com/hashicorp/vagrant"
      version = "~> 1"
    }
    vmware = {
      source  = "github.com/hashicorp/vmware"
      version = "~> 1"
    }
  }
}

variable "boot_wait" {
  type    = string
  default = "30s"
}

variable "ftp_proxy" {
  type    = string
  default = "${env("ftp_proxy")}"
}

variable "http_proxy" {
  type    = string
  default = "${env("http_proxy")}"
}

variable "https_proxy" {
  type    = string
  default = "${env("https_proxy")}"
}

variable "major_version" {
  type    = string
  default = "7"
}

variable "minor_version" {
  type    = string
  default = "1"
}

variable "mirror" {
  type    = string
  default = "https://ftp.lysator.liu.se"
}

source "vmware-iso" "autogenerated_1" {
  boot_command     = [
    "S<enter>",
    "cat <<EOF >>install.conf<enter>",
    "System hostname = openbsd${var.major_version}${var.minor_version}<enter>",
    "Password for root = vagrant<enter>",
    "Setup a user = vagrant<enter>",
    "Password for user = vagrant<enter>",
    "Allow root ssh login = yes<enter>",
    "What timezone are you in = UTC<enter>",
    "Location of sets = cd<enter>",
    "Set name(s) = -game*.tgz -x*.tgz<enter>",
    "Directory does not contain SHA256.sig. Continue without verification = yes<enter>",
    "EOF<enter>", "install -af install.conf && reboot<enter>"
  ]
  boot_wait        = "${var.boot_wait}"
  disk_size        = 10140
  iso_checksum     = "sha256:b70b78a14ce992007615ad6693b61d930344169b9480a63c33c88da35453fc2d"
  iso_url          = "${var.mirror}/pub/OpenBSD/${var.major_version}.${var.minor_version}/arm64/install${var.major_version}${var.minor_version}.img"
  output_directory = "packer-openbsd-${var.major_version}.${var.minor_version}-arm64-vmware"
  shutdown_command = "/sbin/halt -p"
  ssh_password     = "vagrant"
  ssh_port         = 22
  ssh_username     = "root"
  ssh_wait_timeout = "10000s"
  vm_name          = "openbsd-${var.major_version}.${var.minor_version}-arm64"
}

build {
  sources = ["source.vmware-iso.autogenerated_1"]

  provisioner "shell" {
    environment_vars = ["ftp_proxy=${var.ftp_proxy}", "http_proxy=${var.http_proxy}", "https_proxy=${var.https_proxy}"]
    execute_command  = "export {{ .Vars }} && cat {{ .Path }} | su -m"
    scripts          = ["scripts/postinstall.sh", "scripts/vagrant.sh", "scripts/minimize.sh"]
  }

  post-processor "vagrant" {
    output               = "openbsd-${var.major_version}.${var.minor_version}-arm64-{{ .Provider }}.box"
    vagrantfile_template = "Vagrantfile.template"
  }
}
