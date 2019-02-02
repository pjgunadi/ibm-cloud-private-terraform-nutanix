#!/bin/bash
#Create Physical Volumes
pvcreate /dev/sdb

#Create Volume Groups
vgcreate icp-vg /dev/sdb

#Create Logical Volumes
lvcreate -L ${kubelet_lv}G -n kubelet-lv icp-vg
lvcreate -L ${etcd_lv}G -n etcd-lv icp-vg
lvcreate -L ${registry_lv}G -n registry-lv icp-vg
lvcreate -L ${management_lv}G -n management-lv icp-vg
lvcreate -L ${docker_lv}G -n docker-lv icp-vg

#Create Filesystems
mkfs.ext4 /dev/icp-vg/kubelet-lv
mkfs.ext4 /dev/icp-vg/etcd-lv
mkfs.ext4 /dev/icp-vg/registry-lv
mkfs.ext4 /dev/icp-vg/management-lv
mkfs.ext4 /dev/icp-vg/docker-lv

#Create Directories
mkdir -p /var/lib/kubelet
mkdir -p /var/lib/etcd
mkdir -p /var/lib/registry
mkdir -p /var/lib/icp
mkdir -p /var/lib/docker

#Add mount in /etc/fstab
cat <<EOL | tee -a /etc/fstab
/dev/mapper/icp--vg-kubelet--lv /var/lib/kubelet ext4 defaults 0 0
/dev/mapper/icp--vg-etcd--lv /var/lib/etcd ext4 defaults 0 0
/dev/mapper/icp--vg-registry--lv /var/lib/registry ext4 defaults 0 0
/dev/mapper/icp--vg-management--lv /var/lib/icp ext4 defaults 0 0
/dev/mapper/icp--vg-docker--lv /var/lib/docker ext4 defaults 0 0
EOL

#Mount Filesystems
mount -a
