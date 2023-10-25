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
variable "project_count" {
  type    = number
  default = 10
}

locals {
  project_names = [for i in range(var.project_count) : "project-${i + 1}"]
}

resource "libvirt_volume" "madbox" {
  count  = var.project_count
  name   = "madbox-${local.project_names[count.index]}"
  pool   = "default"
  source = "https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.x86_64-Cloud.qcow2"
  format = "qcow2"
}

data "template_file" "user_data" {
  count = var.project_count
  template = file("${path.module}/cloud_init.cfg")
}

data "template_file" "network_config" {
  count = var.project_count
  template = file("${path.module}/network_config.cfg")
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count = var.project_count
  name           = "commoninit-${local.project_names[count.index]}.iso"
  user_data      = data.template_file.user_data[count.index].rendered
  network_config = data.template_file.network_config[count.index].rendered
}

resource "libvirt_domain" "domain-madbox" {
  count = var.project_count
  name   = "madbox-${local.project_names[count.index]}"
  memory = "8192"
  vcpu   = 4

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  network_interface {
    network_name = "madbox.lab"
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
    volume_id = libvirt_volume.madbox[count.index].id
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
