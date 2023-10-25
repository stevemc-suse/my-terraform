terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
    }
  }
}

# instance the provider
provider "libvirt" {
  uri = "qemu:///system"
}

# Generate the project names based on the count of 10
variable "server_count" {
  type    = number
  default = 3
}

variable "base_project_name" {
  type    = string
  default = "madlab"
}

variable "base_network" {
  type    = string
  default = "default"
}

variable "base_dnsname" {
  type    = string
  default = "madbox.lab"
}

variable "base_pool" {
  type    = string
  default = "default"
}

locals {
  project_names = [for i in range(var.server_count) : "${var.base_project_name}-${i + 1}"]
}

resource "libvirt_volume" "domain" {
  count  = var.server_count
  name   = "${local.project_names[count.index]}"
  pool   = "${var.base_pool}"
  source = "https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.x86_64-Cloud.qcow2"
 #  source = "http://10.120.0.4/pub/SLES15-SP5-Minimal-VM.x86_64-Cloud-GM.qcow2"
  format = "qcow2"
}

data "template_file" "user_data" {
  count = var.server_count
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    hostname = "${local.project_names[count.index]}"
    fqdn = "${local.project_names[count.index]}.${var.base_dnsname}"
  }
}

data "template_file" "network_config" {
  count = var.server_count
  template = file("${path.module}/network_config.cfg")
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count = var.server_count
  name           = "commoninit-${local.project_names[count.index]}.iso"
  user_data      = data.template_file.user_data[count.index].rendered
  network_config = data.template_file.network_config[count.index].rendered
}

resource "libvirt_domain" "domain" {
  count = var.server_count
  name   = "${local.project_names[count.index]}"
  memory = "2048"
  vcpu   = 1
#  qemu_agent  = true

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id


provisioner "local-exec" {
   command = "echo ${local.project_names[count.index]}"
}

  network_interface {
    network_name = "${var.base_network}"
    wait_for_lease = true
    hostname = "${local.project_names[count.index]}" 
   }


  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.domain[count.index].id
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

output "hostnames_and_ips" {
  value = [
    for instance in libvirt_domain.domain : {
      hostname = instance.name
      ip_address = instance.network_interface[0].addresses
    }
  ]
}

