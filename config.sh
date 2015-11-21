#!/bin/bash

# Public IP that will be Nat'ed thru to the swarm master
export EXTIP=_your_external_ip_
# Network for the swarm cluster - this must exist already
# (Note dependency on use of '192.168' in sed scripts)
export NETWORK=_your_network_
export DNS=8.8.8.8
export GATEWAY=192.168.3.1
# vCloud Direct host and login credentials
# ('username:password' or 'username' - typically your email address)
export VCDHOST=_your_host_
export VCDLOGIN=_your_username_:_your_password_
# vCloud Org and vDC
export ORG=_your_org_
export VDC=_your_vcd_
# vApp name and hostname forthe swarm master
export MASTERVAPPNAME=coreos-swarm-master
export MASTERVMNAME=master
# Username, public key file, RAM and CPU for all swarm nodes
export USERNAME=core
export PUBKEYFILE=coreos-key.pub
export RAM=4096
export CPU=2
# Naming prefixes for the swarm node vApps and VMs
# For a prefix of 'node', nodes will be named node1, node2, node3
export NODEVAPPPREFIX=coreos-swarm-node
export NODEVMPREFIX=node
# vCloud catalog name (for the CoreOS template and uploaded cloud-config ISOs)
# These should already exist
export CATALOG=_your_catalog_
export TEMPLATE=_your_coreos_template_
