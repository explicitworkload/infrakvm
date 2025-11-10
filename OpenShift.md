# Setup openshift client

Make sure you have infrakvm setup. Let's begin setting up OpenShift.

## Download oc client in jumphost

    curl -o openshift-client.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz

    tar -xvf openshift-client.tar.gz

    sudo mv oc /usr/bin

## Add one 1TB Hard Disk into jumphost

    [shutdown jumphost]
    go to vCenter
    Edit jumphost's Virtual Hardware.
    Add New Device > Hard Disk > Specify 1024GB > Press Ok.
    Actions -> Power On.

![alt text](images/2025-11-10%2017.00.10@2x.png)

Run the following commands in jumphost, use _lsblk_ to check 1TB diskpath is /dev/sdb

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
