#!/bin/bash

# Set environment variables
source config.sh

for VAPPNAME in ${MASTERVAPPNAME} ${NODEVAPPPREFIX}1 ${NODEVAPPPREFIX}2 ${NODEVAPPPREFIX}3
do
  echo "Power off vApp..."
  vca vapp power-off --vapp ${VAPPNAME}
  echo "Delete vApp..."
  vca vapp delete --vapp ${VAPPNAME}
done
echo "Delete NAT rules..."
DNATIP=`vca nat | grep ${EXTIP} | grep DNAT | grep 22 | sed 's/.*192.168/192.168/' | sed 's/ .*//'`
SNATIP=`vca nat | grep ${EXTIP} | grep SNAT | sed 's/.*192.168/192.168/' | sed 's/ .*//'`
vca nat delete --type dnat --original-ip ${EXTIP} --original-port 22 --translated-ip ${DNATIP} --translated-port 22 --protocol tcp
vca nat delete --type dnat --original-ip ${EXTIP} --original-port 2375 --translated-ip ${DNATIP} --translated-port 2375 --protocol tcp
echo "Delete the ISO file..."
vca catalog delete-item --catalog ${CATALOG} --item ${MASTERVMNAME}-config.iso
vca catalog delete-item --catalog ${CATALOG} --item ${NODEVMPREFIX}1-config.iso
vca catalog delete-item --catalog ${CATALOG} --item ${NODEVMPREFIX}2-config.iso
vca catalog delete-item --catalog ${CATALOG} --item ${NODEVMPREFIX}3-config.iso
echo "Delete network..."
#vca network delete --network ${NETWORK}
unset DOCKER_HOST
