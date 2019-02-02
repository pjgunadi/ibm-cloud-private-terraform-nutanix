# Terraform Template for ICP Deployment in VMware

## Before you start
Install your Nutanix cluster environment

## Summary
This terraform template perform the following tasks:
- Provision IBM Cloud Private VMs in Nutanix Cluster
- [Provision ICP and GlusterFS from external module](https://github.com/pjgunadi/terraform-module-icp-deploy)

### Prerequsite - Nutanix Preparation
Before deploying ICP in your Nutanix Cluster environment, verify the following checklist:
1. Ensure you have a valid username and password to access Nutanix
2. For ICP Enterprise edition, download the ICP installer from IBM Passport Advantage and save it in a local SFTP Server
3. Internet connection to download ICP (Community Edition) and OS package dependencies
4. Create Linux VM template with the [supported OS](https://www.ibm.com/support/knowledgecenter/en/SSBS6K_3.1.1/supported_system_config/supported_os.html) of your choice (Ubuntu/RHEL).  
5. The VM template should have:
- minimum disk size of 100GB
- configured with Ubuntu package manager or Red Hat subscription manager. If there is no internet connection, ensure that the VM template has all the pre-requisites pre-installed as defined in [Knowledge Center](https://www.ibm.com/support/knowledgecenter/en/SSBS6K_3.1.1)

## Deployment step from Terraform CLI
1. Clone this repository: `git clone https://github.com/pjgunadi/ibm-cloud-private-terraform-nutanix.git`
2. [Download terraform](https://www.terraform.io/) if you don't have one
3. Rename [terraform_tfvars.sample](terraform_tfvars.sample) file as `terraform.tfvars` and update the input values as needed. 
4. Initialize Terraform to download and update the dependencies
```
terraform init -upgrade
```
5. Review Terraform plan
```
terraform plan
```
6. Apply Terraform template
```
terraform apply
```
**Note:**
You can limit the concurrency with: `terraform apply -parallelism=x` where *x=number of concurrency*

## Add/Remove Proxy/Management/VA/Worker Nodes
1. Edit existing deployed terraform variable e.g. `terraform.tfvars`
2. Increase/decrease the `nodes` and add/remove `ipaddresses` under the node type variable e.g. `worker`. Example:
```
worker = {
    nodes       = "4"
    name        = "worker"
    cpu_cores   = "8"
    cpu_sockets = "1"
    os_disk     = "100"
    kubelet_lv  = "10"
    docker_lv   = "100"
    memory      = "8192"
    ipaddresses = "192.168.1.90,192.168.1.91,192.168.1.92,192.168.1.93"
    netmask     = "24"
    gateway     = "192.168.1.1"
}
```
**Note:** The data disk size is the sume of LV variables + 1 (e.g kubelet_lv + docker_lv + 1).  
2. Re-apply terraform template:
```
terraform plan
terraform apply -auto-approve
```
## ICP and Gluster Provisioning Module
The ICP and GlusterFS Installation is performed by [ICP Provisioning module](https://github.com/pjgunadi/terraform-module-icp-deploy) 

