#!/bin/bash

################################################################
# Module to deploy IBM Cloud Private
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Licensed Materials - Property of IBM
#
# Copyright IBM Corp. 2017.
#
################################################################

if [ ${icp_num_masters} -gt 1 ]; then
  cat <<EOF | tee -a /etc/fstab
${nfs_ip}:/export/icpshared/var/lib/registry   /var/lib/registry    nfs4    auto,nofail,noatime,nolock,intr,tcp,actimeo=1800,rw 0 0
${nfs_ip}:/export/icpshared/var/lib/icp/audit /var/lib/icp/audit    nfs4    auto,nofail,noatime,nolock,intr,tcp,actimeo=1800,rw 0 0
${nfs_ip}:/export/icpshared/var/log/audit    /var/log/audit    nfs4    auto,nofail,noatime,nolock,intr,tcp,actimeo=1800,rw 0 0
EOF

  mount -a
  echo "NFS Mounted"
else
  echo "Skipped mounting NFS"
fi

exit 0
