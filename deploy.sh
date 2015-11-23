#!/bin/bash

# Set environment variables
source config.sh

#echo "Create ${NETWORK} network..."
#vca network create --network ${NETWORK} --gateway-ip ${GATEWAY} --netmask ${NETMASK} --dns1 ${DNS} --pool ${POOL}

echo "Create ${MASTERVMNAME}..."
vca vapp create --vapp ${MASTERVAPPNAME} --vm ${MASTERVMNAME} --template ${TEMPLATE} --catalog ${CATALOG} --network ${NETWORK} --cpu ${CPU} --ram ${RAM}
export MASTERIP=`vca vm | grep ${MASTERVMNAME} | sed 's/.*192.168/192.168/' | sed 's/ .*//'`
export PUBKEY=`cat ${PUBKEYFILE}`

echo "Grab a discovery URL..."
export DISCOVERYURL=`curl https://discovery.etcd.io/new?size=4`

echo "Create 1st master ISO..."
export CLOUD_CONFIG_ISO=${MASTERVMNAME}-config.iso
export TMP_CLOUD_CONFIG_DIR=tmp/master-drive

mkdir -p ${TMP_CLOUD_CONFIG_DIR}/openstack/latest
cat > ${TMP_CLOUD_CONFIG_DIR}/openstack/latest/user_data << __CLOUD_CONFIG__
#cloud-config

hostname: ${MASTERVMNAME}

write_files: 
  - path: /etc/systemd/network/static.network 
    permissions: 0644 
    content: | 
      [Match] 
      Name=en*
      [Network] 
      Address=${MASTERIP}/24 
      Gateway=${GATEWAY}
      DNS=${DNS}
users:
  - name: ${USERNAME}
    primary-group: wheel
    groups:
      - sudo
      - docker
    ssh-authorized-keys:
      - ${PUBKEY}
__CLOUD_CONFIG__

echo "Creating 1st master cloud config ISO ..."
mkisofs -R -V config-2 -o ${CLOUD_CONFIG_ISO} ${TMP_CLOUD_CONFIG_DIR}

echo "Upload ISO..."
#vca catalog upload --catalog ${CATALOG} --item ${CLOUD_CONFIG_ISO} --description ${CLOUD_CONFIG_ISO} --file ${CLOUD_CONFIG_ISO}
ovftool --sourceType='ISO' ${MASTERVMNAME}-config.iso "vcloud://${VCDLOGIN}@${VCDHOST}:?org=${ORG}&vdc=${VDC}&catalog=${CATALOG}&media=${MASTERVMNAME}-config.iso"

echo "Wait for vCloud Director to catch up..."
sleep 30

echo "Insert 1st ISO into VM CD drive..."
vca vapp insert --vapp ${MASTERVAPPNAME} --vm ${MASTERVMNAME} --catalog ${CATALOG} --media ${MASTERVMNAME}-config.iso

echo "Power on vApp..."
vca vapp power-on --vapp ${MASTERVAPPNAME}

echo "Wait..."
sleep 30

echo "Power off vApp..."
vca vapp power-off --vapp ${MASTERVAPPNAME}

echo "Eject 1st ISO from VM CD drive..."
vca vapp eject --vapp ${MASTERVAPPNAME} --vm ${MASTERVMNAME} --catalog ${CATALOG} --media ${MASTERVMNAME}-config.iso  

echo "Create 2nd master ISO..."
#    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
#    listen-client-urls: http://${MASTERIP}:2379,http://${MASTERIP}:4001
cat > ${TMP_CLOUD_CONFIG_DIR}/openstack/latest/user_data << __CLOUD_CONFIG__
#cloud-config

hostname: ${MASTERVMNAME}

write_files: 
  - path: /etc/systemd/network/static.network 
    permissions: 0644 
    content: | 
      [Match] 
      Name=en*
      [Network] 
      Address=${MASTERIP}/24 
      Gateway=${GATEWAY}
      DNS=${DNS}
users:
  - name: ${USERNAME}
    primary-group: wheel
    groups:
      - sudo
      - docker
    ssh-authorized-keys:
      - ${PUBKEY}
      
coreos:
  etcd2:
    discovery: ${DISCOVERYURL}
    advertise-client-urls: http://${MASTERIP}:2379
    initial-advertise-peer-urls: http://${MASTERIP}:2380
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://${MASTERIP}:2380
  units:
    - name: systemd-networkd.service
      command: start
    - name: runcmd.service
      command: start
      content: |
        [Unit]
        Description=Clears and re-creates sshd keys

        [Service]
        Type=oneshot
        ExecStart=/bin/sh -c "rm -f /etc/ssh/*key*; /usr/lib/coreos/sshd_keygen;"
    - name: docker-tcp.socket
      command: start
      enable: true
      content: |
        [Unit]
        Description=Docker Socket for the API

        [Socket]
        ListenStream=4243
        BindIPv6Only=both
        Service=docker.service

        [Install]
        WantedBy=sockets.target
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start
    - name: docker-swarm.service
      command: start
      content: |
        [Unit]
        Description=Swarm service
        After=docker.service

        [Service]
        Restart=on-failure
        RestartSec=10
        ExecStartPre=-/usr/bin/docker ps -q -f status=exited | xargs /usr/bin/docker rm
        ExecStart=/usr/bin/docker run --name docker-swarm -d -p 2375:2375 swarm manage etcd://${MASTERIP}:2379/swarm
  update:
    reboot-strategy: best-effort

__CLOUD_CONFIG__

echo "Creating 2nd master cloud config ISO ..."
mkisofs -R -V config-2 -o ${CLOUD_CONFIG_ISO} ${TMP_CLOUD_CONFIG_DIR}

echo "Upload 2nd master ISO..."
#vca catalog upload --catalog ${CATALOG} --item ${CLOUD_CONFIG_ISO} --description ${CLOUD_CONFIG_ISO} --file ${CLOUD_CONFIG_ISO}
ovftool --overwrite --sourceType='ISO' ${MASTERVMNAME}-config.iso "vcloud://${VCDLOGIN}@${VCDHOST}:?org=${ORG}&vdc=${VDC}&catalog=${CATALOG}&media=${MASTERVMNAME}-config.iso"

echo "Wait for vCloud Director to catch up..."
sleep 30

echo "Insert 2nd master ISO into VM CD drive..."
vca vapp insert --vapp ${MASTERVAPPNAME} --vm ${MASTERVMNAME} --catalog ${CATALOG} --media ${MASTERVMNAME}-config.iso

echo "Create NAT rules..."
vca nat add --type dnat --original-ip ${EXTIP} --original-port 22 --translated-ip ${MASTERIP} --translated-port 22 --protocol tcp
vca nat add --type dnat --original-ip ${EXTIP} --original-port 2375 --translated-ip ${MASTERIP} --translated-port 2375 --protocol tcp
#vca nat add --type snat --original-ip ${MASTERIP} --original-port any --translated-ip ${EXTIP} --translated-port any --protocol any

for I in 1 2 3
do
  export NODEVAPPNAME=${NODEVAPPPREFIX}${I}
  export NODEVMNAME=${NODEVMPREFIX}${I}
  touch ${NODEVMNAME}
  ./deploy-node.sh &
done

echo "Waiting for nodes to build..."
for F in ${NODEVMPREFIX}1 ${NODEVMPREFIX}2 ${NODEVMPREFIX}3
do
  while [ -f ${F} ]
  do
    sleep 5
  done
done
echo

for VAPP in ${MASTERVAPPNAME} ${NODEVAPPPREFIX}1 ${NODEVAPPPREFIX}2 ${NODEVAPPPREFIX}3
do
  echo "Power on ${VAPP}..."
  vca vapp power-on --vapp ${VAPP}
done

echo "Wait..."
sleep 30

echo "Testing docker..."
export DOCKER_HOST=tcp://${EXTIP}:2375
docker info
docker run docker/whalesay cowsay 'It works!'
