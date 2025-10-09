packer {
  required_plugins {
    virtualbox = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/virtualbox"
    }
  }
}

variable "debian_iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-dvd/debian-13.0.0-amd64-DVD-1.iso"
}

variable "debian_iso_checksum" {
  type    = string
  default = "file:https://cdimage.debian.org/debian-cd/current/amd64/iso-dvd/SHA256SUMS"
}

variable "package_version" {
  type    = string
  default = "1.5.0-alpha3"
}

source "virtualbox-iso" "core-poc" {
    guest_os_type = "Debian12_64"
    iso_url = var.debian_iso_url
    iso_checksum = var.debian_iso_checksum
    ssh_username = "defguard"
    ssh_password = "defguard"
    ssh_wait_timeout = "10000s"
    shutdown_command = "echo 'packer' | sudo -S shutdown -P now"
    disk_size = 10240 # 10 GB
    vboxmanage = [
        ["modifyvm", "{{.Name}}", "--memory", "2048"],
        ["modifyvm", "{{.Name}}", "--cpus", "2"],
        ["modifyvm", "{{.Name}}", "--vram", "16"],
        ["modifyvm", "{{.Name}}", "--natdnshostresolver1", "on"],
        # ["modifyvm", "{{.Name}}", "--natdnsproxy1", "on"]
    ]

    http_directory = "http"
    boot_wait = "10s"
    boot_command = [
      "<wait><esc><wait>auto priority=critical ",
      "preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
      "netcfg/get_hostname={{ .Name }} ",
      "netcfg/get_domain=local<enter>",
    ]
}

build {
  sources = ["source.virtualbox-iso.basic-example"]

  provisioner "shell" {
    inline = [
      "echo 'Updating apt repositories...'",
      "sudo apt update -y",
      "echo 'Installing curl...'",
      "sudo apt install -y curl",
      "echo 'Downloading Defguard Core package...'",
      "curl -fsSL -o /tmp/defguard-core.deb https://github.com/DefGuard/defguard/releases/download/v${var.package_version}/defguard-${var.package_version}-x86_64-unknown-linux-gnu.deb",
      "echo 'Installing Defguard Core package...'",
      "sudo dpkg -i /tmp/defguard-core.deb",
    ]
  }
  
  # post-processor "packer" {
  #   keep_input_artifact = true
  #   output = "debian-custom.ovf"
  # }
}
