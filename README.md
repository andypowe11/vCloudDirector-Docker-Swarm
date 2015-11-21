# vCloud Director/vCloud Air Docker cluster using Swarm

A vca-cli script to build a CoreOS-based Docker cluster on vCloud Director
or vCloud Air using Swarm.

## Usage

Do the following:

* Install vca-cli (if you haven't already)
* Log in to vCloud Air or vCloud Director
* Upload a CoreOS OVF file to a suitable catalog on your vCloud Air or
vCloud Director host
* Copy deploy.sh, deploy-node.sh, config.sh and undeploy.sh to the
a directory somewhere
* Edit config.sh to set the variables for your environment
* Run deploy.sh

## Install vca-cli

See https://github.com/vmware/vca-cli but basically:

    pip install vca-cli

Generally, it is sensible to do this in a virtualenv.
You only need to do it once.

## Log in

I'll leave this to you since the parameters will vary depending on whether
you are using vCloud Air or vCloud Director.

For me, it is along the lines of:

    vca login _my_email_ --host vcloud.somewhere.com --org _my_org_ --version 5.6

I'm using vCloud Director.

Note that a username and password (optional) are required in
config.sh but this is just to allow ovftool to upload the ISOs -
I couldn't find a way of making this upload work using vca-cli :-(.

## Add a CoreOS OVF file to your catalog

CoreOS is a small Linux distro used as a container host.
See https://coreos.com/ for details.

You need a copy of a CoreOS .ovf file in a suitable catalog on your
vCloud Air or vCloud Director host so that you can deploy VMs
from it.
You can grab one from http://stable.release.core-os.net/amd64-usr/current/.

See https://blogs.vmware.com/vsphere/2015/03/coreos-now-supported-vmware.html for more details.

You only need to do this once.

## Edit config.sh

Here's what it looks like. Should be pretty self-explanatory, hopefully.

```
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
```

## Run deploy.sh

    ./deploy.sh

This takes a while - sorry, but it is difficult to make things happen in
parallel using vca-cli.  If it works a whale will pop up at the end -
you'll be running a Swarm master and a cluster of 3 nodes. You should be
able to grow this cluster at will but I'll leave that as an exercise for the
reader (look at deploy-node.sh to see how the current nodes
are deployed)!

Swarm is configured to listen on port 2375 (the standard Docker port) at
whatever external IP you've configured into config.sh. So you can
talk to it just like any other Docker host, e.g.:

    docker -H tcp://_your_ext_ip:2375 info

Good luck!

## Tidying up

Fed up with all this Docker stuff? Run

    ./undeploy.sh

to tidy up after yourself :-).

## Behind the scenes

This work was inspired by Paco Gómez's blog post at
http://blog.pacogomez.com/coreos-vcloud-air-on-demand/.

I adopt roughly the same approach to deploying each node in the cluster.

In my case, each node is deployed by generating two ISOs: the first to
configure the networking;
the second to set up etcd2, fleet and swarm.
Each node is therefore booted twice before the cluster comes up.

Swarm is run as a container on each host.
The Swarm nodes advertise themselves via etcd. All nodes form part of the etcd
cluster (i.e. there are 4 of them, 3 nodes and 1 master).
The etcd cluster is created using a token from
https://discovery.etcd.io/new?size=4.
