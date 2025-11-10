## OpenShift Cluster Setup Guide

This guide outlines the steps required to prepare the environment and install the necessary tools for deploying an OpenShift Container Platform cluster.

### Prerequisites

Before you begin, ensure the following requirements are met:

- The `infrakvm` environment is properly set up and accessible. Otherwise, start at [Infrastructure Requirement](README.md)
- A `jumphost` virtual machine is provisioned and running.

### Provision Virtual Machines

Create six virtual machines to serve as the master and worker nodes for the OpenShift cluster. Configure each VM with a unique MAC address according to the specifications below.

| Node Type  | Quantity | vCPU | RAM   | Storage | MAC Address Range                         |
| :--------- | :------- | :--- | :---- | :------ | :---------------------------------------- |
| **Master** | 3        | 8    | 16 GB | Any     | `00:50:56:00:00:01` - `00:50:56:00:00:03` |
| **Worker** | 3        | 16   | 32 GB | Any     | `00:50:56:00:00:04` - `00:50:56:00:00:06` |

### Configure Jumphost Storage

You need to add and configure a dedicated 1 TB disk on the **jumphost** to store installation files and cluster assets.

1.  Power down the **jumphost** VM.
2.  In vCenter, edit the VM's settings to add a new 1 TB hard disk.
3.  Power the **jumphost** back on.
4.  Connect to the **jumphost** and run the following commands to partition, format, and mount the new disk. Verify the new disk is identified as `/dev/sdb` using the `lsblk` command before proceeding.

    ```
    # Verify the disk path
    lsblk

    # Wipe any existing filesystem signatures
    sudo wipefs -a /dev/sdb

    # Initialize the disk as a physical volume for LVM
    sudo pvcreate /dev/sdb

    # Create a volume group named 'vgdata'
    sudo vgcreate vgdata /dev/sdb

    # Create a logical volume named 'lvdata' using all available space
    sudo lvcreate -n lvdata -l 100%FREE vgdata

    # Format the logical volume with an ext4 filesystem
    sudo mkfs.ext4 -L data /dev/vgdata/lvdata

    # Create the mount point
    sudo mkdir -p /data

    # Change ownership of the mount point to your user
    # Replace <username> with your actual username
    sudo chown -R <username> /data

    # Add the new filesystem to /etc/fstab for automatic mounting on boot
    UUID=$(sudo blkid -s UUID -o value /dev/vgdata/lvdata)
    echo "UUID=$UUID /data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

    # Reload daemon services
    sudo systemctl daemon-reload

    # Mount all filesystems listed in /etc/fstab
    sudo mount -a
    ```

### Install OpenShift Client (oc)

Download and install the OpenShift command-line client (`oc`) on the **jumphost**.

1.  Navigate to the newly created data directory.

    ```
    cd /data
    ```

2.  Download the latest stable OpenShift client for Linux from the official mirror.

    ```
    curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
    ```

3.  Extract the contents of the downloaded archive.

    ```
    tar -xvf openshift-client-linux.tar.gz
    ```

4.  Move the `oc` binary to a directory in your system's PATH to make it globally accessible.
    ```
    sudo mv oc /usr/bin/
    ```
