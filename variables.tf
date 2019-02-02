variable "nutanix_user" {
  description = "Nutanix user"
}
variable "nutanix_password" {
  description = "Nutanix password"
}
variable "nutanix_endpoint" {
  description = "Nutanix endpoint"
}
variable "nutanix_port" {
  description = "Nutanix port"
  default = 9440
}
variable "nutanix_cluster_uuid" {
  description = "Nutanix Cluster UUID"
}
variable "nutanix_image_uuid" {
  description = "The UUID of the image to be used for deploy operations."
}
variable "nutanix_network_uuid" {
  description = "The UUID of the network to be used for deploy operations."
}

variable "ssh_user" {
  description = "VM Username"
}

variable "ssh_password" {
  description = "VM Password"
}

variable "timezone" {
  description = "Time Zone"
  default     = "Asia/Singapore"
}

variable "vm_private_key_file" {
  default = "nutanix-key"
}

##### ICP Instance details ######
variable "icp_version" {
  description = "ICP Version"
  default     = "3.1.1"
}

variable "icp_source_server" {
  default = ""
}

variable "icp_source_user" {
  default = ""
}

variable "icp_source_password" {
  default = ""
}

variable "icp_source_path" {
  default = ""
}

variable "icpadmin_password" {
  description = "ICP admin password"
  default     = "admin"
}

variable "network_cidr" {
  default = "172.16.0.0/16"
}

variable "cluster_ip_range" {
  default = "192.168.0.1/24"
}

variable "cluster_vip" {
  default = ""
}

variable "cluster_vip_iface" {
  default = "ens160"
}

variable "proxy_vip" {
  default = ""
}

variable "proxy_vip_iface" {
  default = "ens160"
}

variable "instance_prefix" {
  default = "icp"
}

variable "install_gluster" {
  default = false
}

variable "cluster_name" {
  default = "mycluster"
}

variable "disable_management" {
  default = ["istio", "custom-metrics-adapter"]
}

variable "management_services" {
  type = "map"
  default = {
    istio = "disabled"
    vulnerability-advisor = "disabled"
    storage-glusterfs = "disabled"
    storage-minio = "disabled"
  }
}

variable "kibana_install" {
  default = "false"
}

variable "gluster_volume_type" {
  default = "none"
}

variable "heketi_admin_pwd" {
  default = "none"
}

variable "master" {
  type = "map"

  default = {
    nodes         = "1"
    name          = "master"
    cpu_cores     = "8"
    cpu_sockets   = "1"
    os_disk       = "100"
    kubelet_lv    = "10"
    docker_lv     = "50"
    etcd_lv       = "4"
    registry_lv   = "20"
    management_lv = "20"
    memory        = "8192"
    # ipaddresses   = "192.168.1.81"
    # netmask       = "24"
    # gateway       = "192.168.1.1"
  }
}

variable "proxy" {
  type = "map"

  default = {
    nodes       = "1"
    name        = "proxy"
    cpu_cores   = "4"
    cpu_sockets = "1"
    os_disk     = "100"
    kubelet_lv  = "10"
    docker_lv   = "40"
    memory      = "4096"
    # ipaddresses = "192.168.1.84"
    # netmask     = "24"
    # gateway     = "192.168.1.1"
  }
}

variable "management" {
  type = "map"

  default = {
    nodes         = "1"
    name          = "mgmt"
    cpu_cores     = "8"
    cpu_sockets   = "1"
    os_disk       = "100"
    kubelet_lv    = "10"
    docker_lv     = "40"
    management_lv = "50"
    memory        = "8192"
    # ipaddresses   = "192.168.1.87"
    # netmask       = "24"
    # gateway       = "192.168.1.1"
  }
}

variable "va" {
  type = "map"

  default = {
    nodes         = "1"
    name          = "va"
    cpu_cores     = "8"
    cpu_sockets   = "1"
    os_disk       = "100"
    kubelet_lv    = "10"
    docker_lv     = "40"
    va_lv         = "50"
    memory        = "8192"
    # ipaddresses   = "192.168.1.88"
    # netmask       = "24"
    # gateway       = "192.168.1.1"
  }
}

variable "worker" {
  type = "map"

  default = {
    nodes       = "3"
    name        = "worker"
    cpu_cores   = "8"
    cpu_sockets = "1"
    os_disk     = "100"
    kubelet_lv  = "10"
    docker_lv   = "70"
    memory      = "8192"
    # ipaddresses = "192.168.1.90,192.168.1.91,192.168.1.92"
    # netmask     = "24"
    # gateway     = "192.168.1.1"
  }
}

variable "gluster" {
  type = "map"

  default = {
    nodes       = "0"
    name        = "gluster"
    cpu_cores   = "2"
    cpu_sockets = "1"
    os_disk     = "100"
    data_disk   = "100"                                    // GB
    memory      = "2048"
    # ipaddresses = "192.168.1.95,192.168.1.96,192.168.1.97"
    # netmask     = "24"
    # gateway     = "192.168.1.1"
  }
}

variable "nfs" {
  type = "map"

  default = {
    nodes       = "1"
    name        = "nfs"
    cpu_cores   = "2"
    cpu_sockets = "1"
    os_disk     = "300"
    memory      = "2048"
    # ipaddresses = "192.168.1.98"
    # netmask     = "24"
    # gateway     = "192.168.1.1"
  }
}
