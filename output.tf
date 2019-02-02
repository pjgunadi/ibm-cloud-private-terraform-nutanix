output "icp_url" {
  value = "https://${var.cluster_vip == "" ? nutanix_virtual_machine.master.0.nic_list.0.ip_endpoint_list.0.ip : var.cluster_vip}:8443"
}
