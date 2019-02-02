#!/bin/bash
LOGFILE=/tmp/nfsserver.log
exec > $LOGFILE 2>&1

#Find Linux Distro
if grep -q -i ubuntu /etc/*release
  then
    OSLEVEL=ubuntu
  else
    OSLEVEL=other
fi
echo "Operating System is $OSLEVEL"

ubuntu_install(){
    sudo apt-get -y update
    sudo apt-get install -y apt-transport-https nfs-common ca-certificates curl software-properties-common
    export DEBIAN_FRONTEND=noninteractive
    export DEBIAN_PRIORITY=critical
    sudo -E apt-get -y update
    sudo -E apt-get -yq -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" upgrade
    #sudo apt-get -y upgrade
    sudo apt-get install -y python python-pip socat unzip moreutils

    sudo service iptables stop
    sudo ufw disable
    sudo pip install --upgrade pip
    sudo pip install pyyaml paramiko
}
rhel_install(){
    #Disable SELINUX
    sudo sed -i s/^SELINUX=enforcing/SELINUX=disabled/ /etc/selinux/config && sudo setenforce 0
    sudo systemctl disable firewalld
    sudo systemctl stop firewalld
    #install epel
    #sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    sudo yum -y install python-setuptools policycoreutils-python socat unzip nfs-utils
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2

    sudo easy_install pip
    sudo pip install pyyaml paramiko
}

if [ "$OSLEVEL" == "ubuntu" ]; then
  ubuntu_install
else
  rhel_install
fi

# Start NFS server
sudo systemctl enable nfs-server
sudo systemctl start nfs-server

echo "Complete.."
exit 0
