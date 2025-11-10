# Setup openshift client

Make sure you have infrakvm setup. Let's begin setting up OpenShift.

## Reference Guide

https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/installing_an_on-premise_cluster_with_the_agent-based_installer/preparing-to-install-with-agent-based-installer

# Create Virtual Machines for OpenShift

### Create 6 VM for master and worker nodes

Video tutorial if you need: https://share.cleanshot.com/PMdqHQFc, follow the parameters as follows,

    3 x Master
    - 8 vCPU
    - 16GB RAM
    - Any storage device
    - MAC Address: 00:50:56:00:00:01 to 00:00:03 (assign unique MAC for each of the node)

    3 x Worker
    - 16 vCPU
    - 32GB RAM
    - Any storage device
    - MAC Address: 00:50:56:00:00:04 to 00:00:06 (assign unique MAC for each of the node)

## Add one 1TB Hard Disk into jumphost

    [shutdown jumphost]
    go to vCenter
    Edit jumphost's Virtual Hardware.
    Add New Device > Hard Disk > Specify 1024GB > Press Ok.
    Actions -> Power On.

![alt text](images/2025-11-10%2017.00.10@2x.png)

### Run the following commands in jumphost, use _lsblk_ to check 1TB diskpath is /dev/sdb

    lsblk
    sudo wipefs -a /dev/sdb
    sudo pvcreate /dev/sdb
    sudo vgcreate vgdata /dev/sdb
    sudo lvcreate -n lvdata -l 100%FREE vgdata
    sudo mkfs.ext4 -L data /dev/vgdata/lvdata
    sudo mkdir -p /data
    sudo chown -R <username> /data
    UUID=$(sudo blkid -s UUID -o value /dev/vgdata/lvdata)
    echo "UUID=$UUID /data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    sudo mount -a

## Download oc client in jumphost

    cd /data

    curl -o openshift-client.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz

    tar -xvf openshift-client.tar.gz

    sudo mv oc /usr/bin
