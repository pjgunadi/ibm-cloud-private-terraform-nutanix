#!/bin/bash
DefaultOrg="ibmcom"
DefaultRepo="icp-inception-amd64"
ip=$2

#Node Type List
NODETYPE=$3
if [ "$NODETYPE" == "" ]; then
  NODETYPE="worker"
fi

if [ -z "$4" ]; then
  ICPDIR=/opt/ibm/cluster
else
  ICPDIR=$4
fi

NODELIST=${ICPDIR}/${NODETYPE}list.txt

MASTERNODES=($(cat ${ICPDIR}/masterlist.txt | tr "," " "))

# Populates globals $org $repo $tag
function parse_icpversion() {

  # Determine organisation
  if [[ $1 =~ .*/.* ]]
  then
    org=$(echo $1 | cut -d/ -f1)
  else
    org=$DefaultOrg
  fi
  
  # Determine repository and tag
  if [[ $1 =~ .*:.* ]]
  then
    repo=$(echo $1 | cut -d/ -f2 | cut -d: -f1)
    tag=$(echo $1 | cut -d/ -f2 | cut -d: -f2)
  else
    repo=$DefaultRepo
    tag=$1
  fi
}

parse_icpversion $1

#kubectl="sudo docker run -e LICENSE=accept --net=host -v $ICPDIR:/installer/cluster -v /root:/root $org/$repo:$tag kubectl"
which kubectl || docker run --rm -e LICENSE=accept -v /usr/local/bin:/hostbin $org/$repo:$tag cp /usr/local/bin/kubectl /hostbin/

sudo kubectl config set-cluster cfc-cluster --server=https://${MASTERNODES[0]}:8001 --insecure-skip-tls-verify=true 
sudo kubectl config set-context kubectl --cluster=cfc-cluster 
sudo kubectl config set-credentials user --client-certificate=$ICPDIR/cfc-certs/kubernetes/kubecfg.crt --client-key=$ICPDIR/cfc-certs/kubernetes/kubecfg.key 
sudo kubectl config set-context kubectl --user=user 
sudo kubectl config use-context kubectl
#$kubectl drain $ip --grace-period=300
sudo kubectl drain $ip --force
docker run -e LICENSE=accept --net=host -v "$ICPDIR":/installer/cluster $org/$repo:$tag uninstall -l $ip
sudo kubectl delete node $ip
sudo sed -i "/^$ip.*$/d" /etc/hosts
sudo sed -i "/^$ip.*$/d" /opt/ibm/cluster/hosts
sed -i-$(date +%Y%m%dT%H%M%S) "s/$ip//;s/,*$//;s/,,/,/;s/^,//" $NODELIST