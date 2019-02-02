provider "nutanix" {
  username = "${var.nutanix_user}"
  password = "${var.nutanix_password}"
  endpoint = "${var.nutanix_endpoint}"
  port     = "${var.nutanix_port}"
  insecure = true
}

resource "random_id" "rand" {
  byte_length = 2
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"

  provisioner "local-exec" {
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    command = "chmod 600 ${var.vm_private_key_file}"
  }
}

#Local variables
locals {
  master_datadisk     = "${var.master["kubelet_lv"] + var.master["docker_lv"] + var.master["registry_lv"] + var.master["etcd_lv"] + var.master["management_lv"] + 1}"
  proxy_datadisk      = "${var.proxy["kubelet_lv"] + var.proxy["docker_lv"] + 1}"
  management_datadisk = "${var.management["kubelet_lv"] + var.management["docker_lv"] + var.management["management_lv"] + 1}"
  va_datadisk = "${var.va["kubelet_lv"] + var.va["docker_lv"] + var.va["management_lv"] + 1}"
  worker_datadisk     = "${var.worker["kubelet_lv"] + var.worker["docker_lv"] + 1}"

  #Destroy nodes variables
  icp_boot_node_ip = "${nutanix_virtual_machine.nfs.0.nic_list.0.ip_endpoint_list.0.ip}"
  heketi_ip        = "${nutanix_virtual_machine.gluster.0.nic_list.0.ip_endpoint_list.0.ip}"
  ssh_options      = "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
}

//Script template
data "template_file" "createfs_master" {
  template = "${file("${path.module}/scripts/createfs_master.sh.tpl")}"

  vars {
    kubelet_lv    = "${var.master["kubelet_lv"]}"
    docker_lv     = "${var.master["docker_lv"]}"
    etcd_lv       = "${var.master["etcd_lv"]}"
    registry_lv   = "${var.master["registry_lv"]}"
    management_lv = "${var.master["management_lv"]}"
  }
}

data "template_file" "createfs_proxy" {
  template = "${file("${path.module}/scripts/createfs_proxy.sh.tpl")}"

  vars {
    kubelet_lv = "${var.proxy["kubelet_lv"]}"
    docker_lv  = "${var.proxy["docker_lv"]}"
  }
}

data "template_file" "createfs_management" {
  template = "${file("${path.module}/scripts/createfs_management.sh.tpl")}"

  vars {
    kubelet_lv    = "${var.management["kubelet_lv"]}"
    docker_lv     = "${var.management["docker_lv"]}"
    management_lv = "${var.management["management_lv"]}"
  }
}

data "template_file" "createfs_va" {
  template = "${file("${path.module}/scripts/createfs_va.sh.tpl")}"

  vars {
    kubelet_lv = "${var.va["kubelet_lv"]}"
    docker_lv  = "${var.va["docker_lv"]}"
    va_lv      = "${var.va["va_lv"]}"
  }
}

data "template_file" "createfs_worker" {
  template = "${file("${path.module}/scripts/createfs_worker.sh.tpl")}"

  vars {
    kubelet_lv = "${var.worker["kubelet_lv"]}"
    docker_lv  = "${var.worker["docker_lv"]}"
  }
}

data "template_file" "user_data" {
   template = "${file("${path.module}/scripts/user_data.tpl")}"

   vars {
     password = "${var.ssh_password}"
   }
}

data "template_file" "bootstrap_shared_storage" {
  template = "${file("${path.module}/scripts/bootstrap_shared_storage.tpl")}"

  vars {
    icp_num_masters = "${var.master["nodes"]}"
  }
}

data "template_file" "mount_nfs" {
  template = "${file("${path.module}/scripts/mount_nfs.tpl")}"

  vars {
    nfs_ip          = "${nutanix_virtual_machine.nfs.0.nic_list.0.ip_endpoint_list.0.ip}"
    icp_num_masters = "${var.master["nodes"]}"
  }
}

//NFS
resource "nutanix_virtual_machine" "nfs" {
  lifecycle {
    ignore_changes = ["disk_list.0"]
  }

  #count = "${var.master["nodes"] > 1 ? 1 : 0}"
  count = "${var.nfs["nodes"]}"
  name = "${format("%s-%s-%s-%01d", lower(var.instance_prefix), random_id.rand.hex, lower(var.nfs["name"]),count.index + 1) }"
  num_vcpus_per_socket = "${var.nfs["cpu_sockets"]}"
  num_sockets          = "${var.nfs["cpu_cores"]}"
  memory_size_mib      = "${var.nfs["memory"]}"
  hardware_clock_timezone = "${var.timezone}"

  cluster_reference = {
    kind = "cluster"
    uuid = "${var.nutanix_cluster_uuid}"
  }

  guest_customization_cloud_init_user_data = "${base64encode(data.template_file.user_data.rendered)}"

  nic_list = [
    {
      subnet_reference = {
        kind = "subnet"
        uuid = "${var.nutanix_network_uuid}"
      } 
    },
  ]

  disk_list = [
    {
      disk_size_mib = "${var.nfs["os_disk"] * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
  ]

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
    host     = "${self.nic_list.0.ip_endpoint_list.0.ip}"
  }

  provisioner "file" {
    content     = "${count.index == 0 ? tls_private_key.ssh.private_key_pem : "none"}"
    destination = "${count.index == 0 ? "~/id_rsa" : "/dev/null" }"
  }

  provisioner "file" {
    content     = "${data.template_file.bootstrap_shared_storage.rendered}"
    destination = "/tmp/bootstrap_shared_storage.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/copy/"
    destination = "/tmp/"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/create_nfs.sh"
    destination = "/tmp/create_nfs.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo hostnamectl set-hostname ${self.name}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/bootstrap_shared_storage.sh; sudo /tmp/bootstrap_shared_storage.sh",
      "chmod +x /tmp/create_nfs.sh; /tmp/create_nfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }
}

//master
resource "nutanix_virtual_machine" "master" {
  lifecycle {
    ignore_changes = ["disk_list.0", "disk_list.1"]
  }

  count = "${var.master["nodes"]}"
  name = "${format("%s-%s-%s-%01d", lower(var.instance_prefix), random_id.rand.hex, lower(var.master["name"]),count.index + 1) }"
  num_vcpus_per_socket = "${var.master["cpu_sockets"]}"
  num_sockets          = "${var.master["cpu_cores"]}"
  memory_size_mib      = "${var.master["memory"]}"
  hardware_clock_timezone = "${var.timezone}"


  cluster_reference = {
    kind = "cluster"
    uuid = "${var.nutanix_cluster_uuid}"
  }

  guest_customization_cloud_init_user_data = "${base64encode(data.template_file.user_data.rendered)}"

  nic_list = [
    {
      subnet_reference = {
        kind = "subnet"
        uuid = "${var.nutanix_network_uuid}"
      } 
    },
  ]

  disk_list = [
    {
      disk_size_mib = "${var.master["os_disk"] * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
    {
      disk_size_mib = "${local.master_datadisk * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
  ]

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
    host     = "${self.nic_list.0.ip_endpoint_list.0.ip}"
  }

  provisioner "file" {
    content     = "${count.index == 0 ? tls_private_key.ssh.private_key_pem : "none"}"
    destination = "${count.index == 0 ? "~/id_rsa" : "/dev/null" }"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_master.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    content     = "${data.template_file.mount_nfs.rendered}"
    destination = "/tmp/mount_nfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/copy/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo hostnamectl set-hostname ${self.name}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/mount_nfs.sh; sudo /tmp/mount_nfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }
}

//proxy
resource "nutanix_virtual_machine" "proxy" {
  lifecycle {
    ignore_changes = ["disk_list.0", "disk_list.1"]
  }

  count = "${var.proxy["nodes"]}"
  name = "${format("%s-%s-%s-%01d", lower(var.instance_prefix), random_id.rand.hex, lower(var.proxy["name"]),count.index + 1) }"
  num_vcpus_per_socket = "${var.proxy["cpu_sockets"]}"
  num_sockets          = "${var.proxy["cpu_cores"]}"
  memory_size_mib      = "${var.proxy["memory"]}"
  hardware_clock_timezone = "${var.timezone}"

  cluster_reference = {
    kind = "cluster"
    uuid = "${var.nutanix_cluster_uuid}"
  }

  guest_customization_cloud_init_user_data = "${base64encode(data.template_file.user_data.rendered)}"

  nic_list = [
    {
      subnet_reference = {
        kind = "subnet"
        uuid = "${var.nutanix_network_uuid}"
      } 
    },
  ]

  disk_list = [
    {
      disk_size_mib = "${var.proxy["os_disk"] * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
    {
      disk_size_mib = "${local.proxy_datadisk * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
  ]

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
    host     = "${self.nic_list.0.ip_endpoint_list.0.ip}"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_proxy.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/copy/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo hostnamectl set-hostname ${self.name}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 600 ${var.vm_private_key_file}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "scp -i ${var.vm_private_key_file} ${local.ssh_options} ${path.module}/lib/destroy/delete_node.sh ${var.ssh_user}@${local.icp_boot_node_ip}:/tmp/"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "ssh -i ${var.vm_private_key_file} ${local.ssh_options} ${var.ssh_user}@${local.icp_boot_node_ip} \"chmod +x /tmp/delete_node.sh; /tmp/delete_node.sh ${var.icp_version} ${self.default_ip_address} proxy\"; echo done"
  }
}

//management
resource "nutanix_virtual_machine" "management" {
  lifecycle {
    ignore_changes = ["disk_list.0", "disk_list.1"]
  }

  count = "${var.management["nodes"]}"
  name = "${format("%s-%s-%s-%01d", lower(var.instance_prefix), random_id.rand.hex, lower(var.management["name"]),count.index + 1) }"
  num_vcpus_per_socket = "${var.management["cpu_sockets"]}"
  num_sockets          = "${var.management["cpu_cores"]}"
  memory_size_mib      = "${var.management["memory"]}"
  hardware_clock_timezone = "${var.timezone}"

  cluster_reference = {
    kind = "cluster"
    uuid = "${var.nutanix_cluster_uuid}"
  }

  guest_customization_cloud_init_user_data = "${base64encode(data.template_file.user_data.rendered)}"

  nic_list = [
    {
      subnet_reference = {
        kind = "subnet"
        uuid = "${var.nutanix_network_uuid}"
      } 
    },
  ]

  disk_list = [
    {
      disk_size_mib = "${var.management["os_disk"] * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
    {
      disk_size_mib = "${local.management_datadisk * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
  ]

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
    host     = "${self.nic_list.0.ip_endpoint_list.0.ip}"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_management.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/copy/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo hostnamectl set-hostname ${self.name}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 600 ${var.vm_private_key_file}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "scp -i ${var.vm_private_key_file} ${local.ssh_options} ${path.module}/lib/destroy/delete_node.sh ${var.ssh_user}@${local.icp_boot_node_ip}:/tmp/"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "ssh -i ${var.vm_private_key_file} ${local.ssh_options} ${var.ssh_user}@${local.icp_boot_node_ip} \"chmod +x /tmp/delete_node.sh; /tmp/delete_node.sh ${var.icp_version} ${self.default_ip_address} management\"; echo done"
  }
}

//va
resource "nutanix_virtual_machine" "va" {
  lifecycle {
    ignore_changes = ["disk_list.0", "disk_list.1"]
  }

  count = "${var.va["nodes"]}"
  name = "${format("%s-%s-%s-%01d", lower(var.instance_prefix), random_id.rand.hex, lower(var.va["name"]),count.index + 1) }"
  num_vcpus_per_socket = "${var.va["cpu_sockets"]}"
  num_sockets          = "${var.va["cpu_cores"]}"
  memory_size_mib      = "${var.va["memory"]}"
  hardware_clock_timezone = "${var.timezone}"

  cluster_reference = {
    kind = "cluster"
    uuid = "${var.nutanix_cluster_uuid}"
  }

  guest_customization_cloud_init_user_data = "${base64encode(data.template_file.user_data.rendered)}"

  nic_list = [
    {
      subnet_reference = {
        kind = "subnet"
        uuid = "${var.nutanix_network_uuid}"
      } 
    },
  ]

  disk_list = [
    {
      disk_size_mib = "${var.va["os_disk"] * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
    {
      disk_size_mib = "${local.va_datadisk * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
  ]

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
    host     = "${self.nic_list.0.ip_endpoint_list.0.ip}"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_va.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/copy/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo hostnamectl set-hostname ${self.name}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }

    provisioner "local-exec" {
    when    = "destroy"
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 600 ${var.vm_private_key_file}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "scp -i ${var.vm_private_key_file} ${local.ssh_options} ${path.module}/lib/destroy/delete_node.sh ${var.ssh_user}@${local.icp_boot_node_ip}:/tmp/"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "ssh -i ${var.vm_private_key_file} ${local.ssh_options} ${var.ssh_user}@${local.icp_boot_node_ip} \"chmod +x /tmp/delete_node.sh; /tmp/delete_node.sh ${var.icp_version} ${self.default_ip_address} va\"; echo done"
  }
}

//worker
resource "nutanix_virtual_machine" "worker" {
  lifecycle {
    ignore_changes = ["disk_list.0", "disk_list.1"]
  }

  count = "${var.worker["nodes"]}"
  name = "${format("%s-%s-%s-%01d", lower(var.instance_prefix), random_id.rand.hex, lower(var.worker["name"]),count.index + 1) }"
  num_vcpus_per_socket = "${var.worker["cpu_sockets"]}"
  num_sockets          = "${var.worker["cpu_cores"]}"
  memory_size_mib      = "${var.worker["memory"]}"
  hardware_clock_timezone = "${var.timezone}"

  cluster_reference = {
    kind = "cluster"
    uuid = "${var.nutanix_cluster_uuid}"
  }

  guest_customization_cloud_init_user_data = "${base64encode(data.template_file.user_data.rendered)}"

  nic_list = [
    {
      subnet_reference = {
        kind = "subnet"
        uuid = "${var.nutanix_network_uuid}"
      } 
    },
  ]

  disk_list = [
    {
      disk_size_mib = "${var.worker["os_disk"] * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
    {
      disk_size_mib = "${local.worker_datadisk * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
  ]

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
    host     = "${self.nic_list.0.ip_endpoint_list.0.ip}"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_worker.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/scripts/copy/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo hostnamectl set-hostname ${self.name}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 600 ${var.vm_private_key_file}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "scp -i ${var.vm_private_key_file} ${local.ssh_options} ${path.module}/lib/destroy/delete_node.sh ${var.ssh_user}@${local.icp_boot_node_ip}:/tmp/"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "ssh -i ${var.vm_private_key_file} ${local.ssh_options} ${var.ssh_user}@${local.icp_boot_node_ip} \"chmod +x /tmp/delete_node.sh; /tmp/delete_node.sh ${var.icp_version} ${self.default_ip_address} worker\"; echo done"
  }
}

//gluster
resource "nutanix_virtual_machine" "gluster" {
  lifecycle {
    ignore_changes = ["disk_list.0", "disk_list.1"]
  }

  count = "${var.gluster["nodes"]}"
  name = "${format("%s-%s-%s-%01d", lower(var.instance_prefix), random_id.rand.hex, lower(var.gluster["name"]),count.index + 1) }"
  num_vcpus_per_socket = "${var.gluster["cpu_sockets"]}"
  num_sockets          = "${var.gluster["cpu_cores"]}"
  memory_size_mib      = "${var.gluster["memory"]}"
  hardware_clock_timezone = "${var.timezone}"

  cluster_reference = {
    kind = "cluster"
    uuid = "${var.nutanix_cluster_uuid}"
  }

  guest_customization_cloud_init_user_data = "${base64encode(data.template_file.user_data.rendered)}"

  nic_list = [
    {
      subnet_reference = {
        kind = "subnet"
        uuid = "${var.nutanix_network_uuid}"
      } 
    },
  ]

  disk_list = [
    {
      disk_size_mib = "${var.gluster["os_disk"] * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
    {
      disk_size_mib = "${var.gluster["data_disk"] * 1024 }"
      data_source_reference = {
        kind = "image"
        uuid = "${var.nutanix_image_uuid}"
      }
    },
  ]

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
    host     = "${self.nic_list.0.ip_endpoint_list.0.ip}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo hostnamectl set-hostname ${self.name}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "sudo mkdir /root/.ssh && sudo chmod 700 /root/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | sudo tee -a /root/.ssh/authorized_keys && sudo chmod 600 /root/.ssh/authorized_keys",
    ]
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 600 ${var.vm_private_key_file}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "scp -i ${var.vm_private_key_file} ${local.ssh_options} ${path.module}/lib/destroy/delete_gluster.sh ${var.ssh_user}@${local.heketi_ip}:/tmp/"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "ssh -i ${var.vm_private_key_file} ${local.ssh_options} ${var.ssh_user}@${local.heketi_ip} \"chmod +x /tmp/delete_gluster.sh; /tmp/delete_gluster.sh ${self.default_ip_address}\"; echo done"
  }
}

# Copy Delete scripts
resource "null_resource" "copy_delete_node" {
  connection {
    host        = "${local.icp_boot_node_ip}"
    user        = "${var.ssh_user}"
    private_key = "${tls_private_key.ssh.private_key_pem}"
  }

  provisioner "file" {
    source      = "${path.module}/lib/destroy/delete_node.sh"
    destination = "/tmp/delete_node.sh"
  }
}

resource "null_resource" "copy_delete_gluster" {
  connection {
    host        = "${local.heketi_ip}"
    user        = "${var.ssh_user}"
    private_key = "${tls_private_key.ssh.private_key_pem}"
  }

  provisioner "file" {
    source      = "${path.module}/lib/destroy/delete_gluster.sh"
    destination = "/tmp/delete_gluster.sh"
  }
}

//spawn ICP Installation
module "icpprovision" {
  source = "github.com/pjgunadi/terraform-module-icp-deploy?ref=test"

  //Connection IPs
  icp-ips = "${concat(nutanix_virtual_machine.nfs.*.nic_list.0.ip_endpoint_list.0.ip)}"

  boot-node = "${element(nutanix_virtual_machine.nfs.*.nic_list.0.ip_endpoint_list.0.ip, 0)}"

  //Configuration IPs
  icp-master     = ["${nutanix_virtual_machine.master.*.nic_list.0.ip_endpoint_list.0.ip}"]
  icp-worker     = ["${nutanix_virtual_machine.worker.*.nic_list.0.ip_endpoint_list.0.ip}"]
  icp-proxy      = ["${split(",",var.proxy["nodes"] == 0 ? join(",",nutanix_virtual_machine.master.*.nic_list.0.ip_endpoint_list.0.ip) : join(",",nutanix_virtual_machine.proxy.*.nic_list.0.ip_endpoint_list.0.ip))}"]
  icp-management = ["${split(",",var.management["nodes"] == 0 ? "" : join(",",nutanix_virtual_machine.management.*.nic_list.0.ip_endpoint_list.0.ip))}"]
  icp-va         = ["${split(",",var.va["nodes"] == 0 ? "" : join(",",nutanix_virtual_machine.va.*.nic_list.0.ip_endpoint_list.0.ip))}"]

  # Workaround for terraform issue #10857
  cluster_size    = "${var.nfs["nodes"]}"
  master_size     = "${var.master["nodes"]}"
  worker_size     = "${var.worker["nodes"]}"
  proxy_size      = "${var.proxy["nodes"]}"
  management_size = "${var.management["nodes"]}"
  va_size         = "${var.va["nodes"]}"

  icp_source_server   = "${var.icp_source_server}"
  icp_source_user     = "${var.icp_source_user}"
  icp_source_password = "${var.icp_source_password}"
  image_file          = "${var.icp_source_path}"

  icp-version = "${var.icp_version}"

  icp_configuration = {
    "cluster_name"                 = "${var.cluster_name}"
    "network_cidr"                 = "${var.network_cidr}"
    "service_cluster_ip_range"     = "${var.cluster_ip_range}"
    "ansible_user"                 = "${var.ssh_user}"
    "ansible_become"               = "${var.ssh_user == "root" ? false : true}"
    "default_admin_password"       = "${var.icpadmin_password}"
    #"calico_ipip_enabled"          = "true"
    "docker_log_max_size"          = "100m"
    "docker_log_max_file"          = "10"
    #"disabled_management_services" = ["${split(",",var.va["nodes"] != 0 ? join(",",var.disable_management) : join(",",concat(list("vulnerability-advisor"),var.disable_management)))}"]
    "cluster_vip"                  = "${var.cluster_vip == "" ? element(nutanix_virtual_machine.master.*.nic_list.0.ip_endpoint_list.0.ip, 0) : var.cluster_vip}"
    "vip_iface"                    = "${var.cluster_vip_iface == "" ? "eth0" : var.cluster_vip_iface}"
    "proxy_vip"                    = "${var.proxy_vip == "" ? element(split(",",var.proxy["nodes"] == 0 ? join(",",nutanix_virtual_machine.master.*.nic_list.0.ip_endpoint_list.0.ip) : join(",",nutanix_virtual_machine.proxy.*.nic_list.0.ip_endpoint_list.0.ip)), 0) : var.proxy_vip}"
    "proxy_vip_iface"              = "${var.proxy_vip_iface == "" ? "eth0" : var.proxy_vip_iface}"

    "management_services" = {
      "istio" = "${var.management_services["istio"]}"
      "vulnerability-advisor" = "${var.va["nodes"] != 0 ? var.management_services["vulnerability-advisor"] : "disabled"}"
      "storage-glusterfs" = "${var.management_services["storage-glusterfs"]}"
      "storage-minio" = "${var.management_services["storage-minio"]}"
    }
    #"kibana_install"               = "${var.kibana_install}"

 }

  #Gluster
  install_gluster = "${var.install_gluster}"

  gluster_size        = "${var.gluster["nodes"]}"
  gluster_ips         = ["${nutanix_virtual_machine.gluster.*.nic_list.0.ip_endpoint_list.0.ip}"] #Connecting IP
  gluster_svc_ips     = ["${nutanix_virtual_machine.gluster.*.nic_list.0.ip_endpoint_list.0.ip}"] #Service IP
  device_name         = "/dev/sdb"                                                  #update according to the device name provided by cloud provider
  heketi_ip           = "${nutanix_virtual_machine.gluster.0.nic_list.0.ip_endpoint_list.0.ip}"   #Connectiong IP
  heketi_svc_ip       = "${nutanix_virtual_machine.gluster.0.nic_list.0.ip_endpoint_list.0.ip}"   #Service IP
  cluster_name        = "${var.cluster_name}.icp"
  gluster_volume_type = "${var.gluster_volume_type}"
  heketi_admin_pwd    = "${var.heketi_admin_pwd}"
  generate_key        = true

  #icp_pub_keyfile = "${tls_private_key.ssh.public_key_openssh}"
  #icp_priv_keyfile = "${tls_private_key.ssh.private_key_pem"}"

  ssh_user = "${var.ssh_user}"
  ssh_key  = "${tls_private_key.ssh.private_key_pem}"

  bastion_host = "${local.icp_boot_node_ip}"
  bastion_user = "${var.ssh_user}"
  bastion_private_key = "${tls_private_key.ssh.private_key_pem}"  
}
