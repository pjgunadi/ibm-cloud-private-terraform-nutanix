# ICP Deployment in Nutanix with IBM CAM

## Before you start
Install your Nutanix environment

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
- minimum disk size of 100 GB
- configured with Ubuntu package manager or Red Hat subscription manager. If there is no internet connection, ensure that the VM template has all the pre-requisites pre-installed as defined in [Knowledge Center](https://www.ibm.com/support/knowledgecenter/en/SSBS6K_3.1.1)

## Deployment step from IBM CAM
1. Login into IBM CAM
2. Create Template with the following details:
  - From GitHub
  - GitHub Repository URL: `https://github.com/pjgunadi/ibm-cloud-private-terraform-nutanix`
  - GitHub Repository sub-directory: `cam`
4. Click `Create` and `Save`
5. Deploy the template

## Add/Remove Worker Nodes
1. Open Deployed Instance in CAM
2. Open `Modify` tab
3. Click `Next`
4. Increase/decrease the **Worker Node** `nodes` attribute and and add/remove `ipaddresses` attribute
5. Click `Plan Changes`
6. Review the plan in the Log Output and click `Apply Changes`

**Note:** The data disk size is the sume of LV variables + 1 (e.g kubelet_lv + docker_lv + 1).  

## ICP and Gluster Provisioning Module
The ICP and GlusterFS Installation is performed by [ICP Provisioning module](https://github.com/pjgunadi/terraform-module-icp-deploy) 
