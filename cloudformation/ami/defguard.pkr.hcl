packer {
  required_plugins {
    amazon = {
      version = ">= 1.6.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "core_version" {
  type = string
}

variable "gateway_version" {
  type = string
}

variable "proxy_version" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

source "amazon-ebs" "defguard" {
  ami_name      = "defguard-C-${var.core_version}-PX-${var.gateway_version}-GW-${var.proxy_version}-amd64"
  instance_type = var.instance_type
  region        = var.region
  source_ami_filter {
    filters = {
      name                = "debian-13-amd64-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["136693071363"]
  }
  ssh_username = "admin"
}

build {
  name = "defguard"
  sources = [
    "source.amazon-ebs.defguard"
  ]

  provisioner "shell" {
    script = "./cloudformation/ami/defguard-install.sh"
    environment_vars = [
      "CORE_VERSION=${var.core_version}",
      "PROXY_VERSION=${var.proxy_version}",
      "GATEWAY_VERSION=${var.gateway_version}"
    ]
  }

  provisioner "shell" {
    inline = ["rm /home/admin/.ssh/authorized_keys"]
  }

  provisioner "shell" {
    inline = ["sudo rm /root/.ssh/authorized_keys"]
  }
}
