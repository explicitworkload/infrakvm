## OpenShift Cluster Setup Guide

This guide outlines the steps required to prepare the environment and install the necessary tools for deploying an OpenShift Container Platform cluster.

### Prerequisites

Before you begin, ensure the following requirements are met:

- The `infrakvm` environment is properly set up and accessible. Otherwise, start at [Infrastructure Requirement](README.md)
- A `jumphost` virtual machine is provisioned and running.

## Step 1. Provision Virtual Machines

1. Create six virtual machines to serve as the master and worker nodes for the OpenShift cluster. Configure each VM with a unique MAC address according to the specifications below.

   | Node Type  | Quantity | vCPU | RAM   | Storage1 | Storage2 | MAC Address Range                         |
   | :--------- | :------- | :--- | :---- | :------- | :------- | :---------------------------------------- |
   | **Master** | 3        | 8    | 16 GB | 120GB    | 50GB     | `00:50:56:00:00:01` - `00:50:56:00:00:03` |
   | **Worker** | 3        | 16   | 32 GB | 120GB    | 50GB     | `00:50:56:00:00:04` - `00:50:56:00:00:06` |

   > 💬 **Note:**  
   > You can name them master-1, master-2, master-3, worker-1, worker-2, worker-3...

2. Add disk.EnableUUID=true in each of the VM.

   <em>(Specific to VMware only) Enabling `disk.EnableUUID=true` exposes the virtual disk's unique identifier (UUID) to the guest operating system. This is critical for an OpenShift cluster, as it allows Kubernetes to reliably identify and attach the correct persistent storage volumes to nodes. Without this setting, storage may fail to mount properly, leading to application downtime.</em>

   - Navigate to Edit Settings and select the Advanced Parameters section.
   - In the **Attribute** column, type `disk.EnableUUID`.
   - In the **Value** column, type `TRUE`.
   - Click ADD and click Ok to save the changes.

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

---

## Step 2. Install OpenShift Client (oc)

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
    sudo mv oc kubectl /usr/bin/
    ```

---

## Step 3. OpenShift Installation (Agent-Based, Air-Gapped)

Installing OpenShift in an air-gapped (or disconnected) environment requires mirroring the necessary container images to a local registry that your cluster can access. The agent-based installer simplifies the node provisioning process.

#### 1. Set Up a Local Mirror Registry

Your air-gapped environment needs a local container registry to store the OpenShift images. This registry has been pre-installed for you at https://quay.kubernetes.day/ so that you can skip this portion. Take note the lightweight mirror-registry is not meant for production usage.

#### 2. Mirror the OpenShift Images

Since the environment is (simulated) air-gapped, you'll still need to download the OpenShift images on a machine with internet access and then transfer them to your jumphost.

1. On the jumphost, download the oc-mirror tool:

   ```
   curl -o oc-mirror.tar.gz https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/oc-mirror.rhel9.tar.gz
   tar -xvf oc-mirror.tar.gz
   sudo mv oc-mirror /usr/bin
   ```

2. Validate oc-mirror is working

   ```
   oc-mirror version
   ```

3. Create an `imageset-config.yaml` file.

   This file specifies which OpenShift version and operator images to mirror. Use a reference imageset configuration and build on from there.

   - [isc.yaml](ocp/oc-mirror/isc.yaml)
   - [isc-additional.yaml](ocp/oc-mirror/isc-additional.yaml)

4. Mirror the images to a directory:

   Run the oc-mirror command to download the images specified in your imageset-config.yaml.

   ```
   oc-mirror --config=~/infrakvm/ocp/oc-mirror/isc.yaml file:///data/mirror/ --v2
   ```

   This will create a mirror_seq<#>.tar file in the /data/mirror directory.

5. Push the images to your local mirror registry:

   On the jumphost, unpack the mirrored data and push it to your local registry.

   ```
   # Navigate to the mirrored data directory
   mkdir -p /data/mirror && cd /data/mirror

   # Push the images to your local registry
   oc-mirror --from=./mirror_seq1.tar docker://quay.kubernetes.day --v2
   ```
