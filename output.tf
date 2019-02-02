output "icp_url" {
  value = "https://${var.cluster_vip == "" ? element(nutanix_virtual_machine.master.*.nic_list.0.ip_endpoint_list.0.ip, 0) : var.cluster_vip}:8443"
}
