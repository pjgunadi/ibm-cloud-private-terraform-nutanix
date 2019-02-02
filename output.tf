output "icp_url" {
  value = "https://${var.cluster_vip == "" ? element(nutanix_virtual_machine.master.*.default_ip_address, 0) : var.cluster_vip}:8443"
}
