packer {
  required_plugins {
    qemu = {
      version = ">= 1.0.9"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "vm_name"   { default = "defguard" }
variable "disk_size" { default = "20G" }
variable "memory"    { default = 2048 }
variable "cpus"      { default = 2 }
variable "ssh_user"     { default = "ubuntu" }
variable "iso_url"      { default = "https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-live-server-amd64.iso" }
variable "core_tag"     { type = string }
variable "proxy_tag"    { type = string }
variable "gateway_tag"  { type = string }

source "qemu" "ubuntu24" {
  iso_url      = var.iso_url
  iso_checksum = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"

  vm_name          = var.vm_name
  memory           = var.memory
  cpus             = var.cpus
  disk_size        = var.disk_size
  accelerator      = "kvm"
  format           = "qcow2"
  output_directory = "output/${var.vm_name}"

  net_device     = "virtio-net"
  disk_interface = "virtio"
  machine_type   = "q35"

  ssh_username           = var.ssh_user
  ssh_password           = "ubuntu"
  ssh_timeout            = "40m"
  ssh_handshake_attempts = 100

  http_content = {
    "/meta-data" = file("${path.root}/http/meta-data")
    "/user-data" = file("${path.root}/http/user-data")
  }
  boot_wait = "5s"
  boot_command = [
    "c<wait5>",
    "linux /casper/vmlinuz autoinstall 'ds=nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<enter><wait5>",
    "initrd /casper/initrd<enter><wait5>",
    "boot<enter>"
  ]

  shutdown_command = "sudo shutdown -P now"
  headless         = true
}

build {
  sources = ["source.qemu.ubuntu24"]

  provisioner "file" {
    source      = "files/docker-setup.sh"
    destination = "/tmp/docker-setup.sh"
  }

  provisioner "file" {
    source      = "files/99-defguard.cfg"
    destination = "/tmp/99-defguard.cfg"
  }

  provisioner "file" {
    source      = "files/docker-compose.yaml"
    destination = "/tmp/docker-compose.yaml"
  }

  provisioner "file" {
    source      = "files/docker-compose.standalone.yaml"
    destination = "/tmp/docker-compose.standalone.yaml"
  }

  provisioner "file" {
    source      = "files/generate-env.sh"
    destination = "/tmp/generate-env.sh"
  }

  provisioner "file" {
    source      = "files/start.sh"
    destination = "/tmp/start.sh"
  }

  provisioner "file" {
    source      = "files/defguard-init.service"
    destination = "/tmp/defguard-init.service"
  }

  provisioner "shell" {
    inline = [
      "sudo bash /tmp/docker-setup.sh",
      "sudo mkdir -p /opt/stacks/defguard",
      "sudo mv /tmp/docker-compose.yaml /opt/stacks/defguard/docker-compose.yaml",
      "sudo mv /tmp/docker-compose.standalone.yaml /opt/stacks/defguard/docker-compose.standalone.yaml",
      "sudo mv /tmp/generate-env.sh /opt/stacks/defguard/generate-env.sh",
      "sudo chmod +x /opt/stacks/defguard/generate-env.sh",
      "sudo mv /tmp/start.sh /opt/stacks/defguard/start.sh",
      "sudo chmod +x /opt/stacks/defguard/start.sh",
      "echo 'DEFGUARD_CORE_TAG=${var.core_tag}' | sudo tee /opt/stacks/defguard/.image-tags > /dev/null",
      "echo 'DEFGUARD_PROXY_TAG=${var.proxy_tag}' | sudo tee -a /opt/stacks/defguard/.image-tags > /dev/null",
      "echo 'DEFGUARD_GATEWAY_TAG=${var.gateway_tag}' | sudo tee -a /opt/stacks/defguard/.image-tags > /dev/null",
      "sudo mv /tmp/99-defguard.cfg /etc/cloud/cloud.cfg.d/99-defguard.cfg",
      "sudo mv /tmp/defguard-init.service /etc/systemd/system/defguard-init.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable docker.service",
      "sudo chown -R ubuntu:ubuntu /opt/stacks/defguard",
      "sudo rm -f /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml",
      "sudo cloud-init clean --logs",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo rm -f /root/.ssh/authorized_keys",
      "sudo rm -f /home/ubuntu/.ssh/authorized_keys",
      "sudo truncate -s 0 /home/ubuntu/.bash_history || true",
      "sudo truncate -s 0 /root/.bash_history || true",
      # Expire default password so it must be changed on first login
      "sudo chage -d 0 ubuntu"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "qemu-img convert -f qcow2 -O vmdk output/${var.vm_name}/${var.vm_name} output/${var.vm_name}/${var.vm_name}.vmdk",
      "cp files/ubuntu.vmx output/${var.vm_name}/${var.vm_name}.vmx",
      "ovftool --lax --diskMode=thin output/${var.vm_name}/${var.vm_name}.vmx output/${var.vm_name}/${var.vm_name}.ova"
    ]
  }
}
