#!/bin/bash

echo "Create ${NODEVMNAME}..."
vca vapp create --vapp ${NODEVAPPNAME} --vm ${NODEVMNAME} --template ${TEMPLATE} --catalog ${CATALOG} --network ${NETWORK} --cpu ${CPU} --ram ${RAM}
export NODEIP=`vca vm | grep ${NODEVMNAME} | sed 's/.*192.168/192.168/' | sed 's/ .*//'`
echo "IP address of ${NODEVMNAME} is ${NODEIP}"

echo "Create 1st node ISO..."
export CLOUD_CONFIG_ISO=${NODEVMNAME}-config.iso
export TMP_CLOUD_CONFIG_DIR=tmp/${NODEVMNAME}-drive

mkdir -p ${TMP_CLOUD_CONFIG_DIR}/openstack/latest
cat > ${TMP_CLOUD_CONFIG_DIR}/openstack/latest/user_data << __CLOUD_CONFIG__
#cloud-config

hostname: ${NODEVMNAME}

write_files: 
  - path: /etc/systemd/network/static.network 
    permissions: 0644 
    content: | 
      [Match] 
      Name=en*
      [Network] 
      Address=${NODEIP}/24 
      Gateway=${GATEWAY}
      DNS=8.8.8.8
users:
  - name: ${USERNAME}
    primary-group: wheel
    groups:
      - sudo
      - docker
    ssh-authorized-keys:
      - ${PUBKEY}
__CLOUD_CONFIG__
  
echo "Creating 1st node cloud config ISO ..."
mkisofs -R -V config-2 -o ${CLOUD_CONFIG_ISO} ${TMP_CLOUD_CONFIG_DIR}

echo "Upload ISO..."
#vca catalog upload --catalog ${CATALOG} --item ${CLOUD_CONFIG_ISO} --description ${CLOUD_CONFIG_ISO} --file ${CLOUD_CONFIG_ISO}
ovftool --sourceType='ISO' ${NODEVMNAME}-config.iso "vcloud://${VCDLOGIN}@${VCDHOST}:?org=${ORG}&vdc=${VDC}&catalog=${CATALOG}&media=${NODEVMNAME}-config.iso"

echo "Wait for vCloud Director to catch up..."
sleep 30

echo "Insert 1st ISO into VM CD drive..."
vca vapp insert --vapp ${NODEVAPPNAME} --vm ${NODEVMNAME} --catalog ${CATALOG} --media ${NODEVMNAME}-config.iso

echo "Power on vApp..."
vca vapp power-on --vapp ${NODEVAPPNAME}

echo "Wait..."
sleep 30

echo "Power off vApp..."
vca vapp power-off --vapp ${NODEVAPPNAME}

echo "Eject 1st ISO from VM CD drive..."
vca vapp eject --vapp ${NODEVAPPNAME} --vm ${NODEVMNAME} --catalog ${CATALOG} --media ${NODEVMNAME}-config.iso

echo "Create 2nd node ISO..."
#    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
#    listen-client-urls: http://${NODEIP}:2379,http://${NODEIP}:4001
cat > ${TMP_CLOUD_CONFIG_DIR}/openstack/latest/user_data << __CLOUD_CONFIG__
#cloud-config

hostname: ${NODEVMNAME}

write_files: 
  - path: /etc/systemd/network/static.network 
    permissions: 0644 
    content: | 
      [Match] 
      Name=en*
      [Network] 
      Address=${NODEIP}/24 
      Gateway=${GATEWAY}
      DNS=8.8.8.8
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
    advertise-client-urls: http://${NODEIP}:2379
    initial-advertise-peer-urls: http://${NODEIP}:2380
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://${NODEIP}:2380
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
        ExecStart=/usr/bin/docker run --name docker-swarm -d swarm join --addr=${NODEIP}:4243 etcd://${NODEIP}:2379/swarm
  update:
    reboot-strategy: best-effort

__CLOUD_CONFIG__
  
echo "Creating 2nd node cloud config ISO ..."
mkisofs -R -V config-2 -o ${CLOUD_CONFIG_ISO} ${TMP_CLOUD_CONFIG_DIR}

echo "Upload 2nd node ISO..."
#vca catalog upload --catalog ${CATALOG} --item ${CLOUD_CONFIG_ISO} --description ${CLOUD_CONFIG_ISO} --file ${CLOUD_CONFIG_ISO}
ovftool --overwrite --sourceType='ISO' ${NODEVMNAME}-config.iso "vcloud://${VCDLOGIN}@${VCDHOST}:?org=${ORG}&vdc=${VDC}&catalog=${CATALOG}&media=${NODEVMNAME}-config.iso"

echo "Wait for vCloud Director to catch up..."
sleep 30

echo "Insert 2nd node ISO into VM CD drive..."
vca vapp insert --vapp ${NODEVAPPNAME} --vm ${NODEVMNAME} --catalog ${CATALOG} --media ${NODEVMNAME}-config.iso

echo "$NODEVAPPNAME ready..."
rm -f ${NODEVMNAME}
