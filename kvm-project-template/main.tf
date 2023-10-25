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

# Define the project names and count
variable "project_names" {
  type    = list(string)
  default = ["project-0", "project-1", "project-2", "project-3", "project-4"]
}

# Define a count based on the number of project names
locals {
  machine_count = length(var.project_names)
}

resource "libvirt_volume" "madbox" {
  count  = local.machine_count
  name   = "${var.project_names[count.index]}"
  pool   = "default"
  source = "https://download.opensuse.org/distribution/leap/15.5/appliances/openSUSE-Leap-15.5-Minimal-VM.x86_64-Cloud.qcow2"
  format = "qcow2"
}

data "template_file" "user_data" {
  count = local.machine_count
  template = file("${path.module}/cloud_init.cfg")
  vars = {
    hostname = "${var.project_names[count.index]}"
    fqdn = "${var.project_names[count.index]}.madbox.lab}"
  }
}

data "template_file" "network_config" {
  count = local.machine_count
  template = file("${path.module}/network_config.cfg")
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count = local.machine_count
  name           = "commoninit-${var.project_names[count.index]}.iso"
  user_data      = data.template_file.user_data[count.index].rendered
  network_config = data.template_file.network_config[count.index].rendered
}

resource "libvirt_domain" "domain-madbox" {
  count = local.machine_count
  name   = "${var.project_names[count.index]}"
  memory = "8192"
  vcpu   = 4

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

provisioner "local-exec" {
   command = "echo ${var.project_names[count.index]}" 
}

  network_interface {
    network_name = "madbox.lab"
    wait_for_lease = true
    hostname       = "${var.project_names[count.index]}"
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

