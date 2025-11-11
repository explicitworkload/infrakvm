# OpenShift Cluster Setup Guide

This guide details the process for preparing the environment and deploying an OpenShift Container Platform cluster using the agent-based, air-gapped installation method.

## Step 1: Prepare the Infrastructure

This section covers provisioning the virtual machines for the cluster and configuring the storage on the jumphost.

### Prerequisites

Before you begin, ensure the following requirements are met:

- The `infrakvm` environment is properly set up and accessible. If not, refer to the infrastructure requirements documentation.
- A `jumphost` virtual machine is provisioned and running.

### Provision Cluster Nodes

Provision six virtual machines with the following specifications. For easy identification, you can name the nodes `master-1`, `master-2`, `master-3`, `worker-1`, `worker-2`, and `worker-3`.

| Node Type  | Quantity | vCPU | RAM   | Storage | MAC Address Range                         |
| :--------- | :------- | :--- | :---- | :------ | :---------------------------------------- |
| **Master** | 3        | 8    | 16 GB | 120 GB  | `00:50:56:00:00:01` - `00:50:56:00:00:03` |
| **Worker** | 3        | 16   | 32 GB | 120 GB  | `00:50:56:00:00:04` - `00:50:56:00:00:06` |

### Enable Disk UUID on VMware VMs

> In a VMware environment, enabling `disk.EnableUUID=true` is critical. It exposes the virtual disk's unique identifier (UUID) to the guest OS, allowing Kubernetes to reliably identify and attach the correct persistent storage volumes. Without this setting, storage may fail to mount properly.

To enable this setting on each VM:

1.  Navigate to **Edit Settings** and select the **VM Options** tab.
2.  Expand the **Advanced** section and click **Edit Configuration**.
3.  Click **Add Configuration Params**.
4.  In the **Name** column, enter `disk.EnableUUID`.
5.  In the **Value** column, enter `TRUE`.
6.  Click **OK** to save the changes.

### Configure Jumphost Storage

Add and configure a dedicated 1 TB disk on the **jumphost** to store installation files and cluster assets.

1.  Power down the **jumphost** VM.
2.  In your hypervisor, edit the VM's settings to add a new 1 TB hard disk.
3.  Power the **jumphost** back on.
4.  Connect to the **jumphost** and run the following commands to partition, format, and mount the new disk.

> ⚠️ **Important:** Before proceeding, run `lsblk` to verify the new disk is identified as `/dev/sdb`. Adjust the device path if necessary.

```
# Wipe any existing filesystem signatures from the new disk
sudo wipefs -a /dev/sdb

# Initialize the disk as a physical volume for LVM
sudo pvcreate /dev/sdb

# Create a volume group named 'vgdata'
sudo vgcreate vgdata /dev/sdb

# Create a logical volume named 'lvdata' that uses all available space
sudo lvcreate -n lvdata -l 100%FREE vgdata

# Format the logical volume with an ext4 filesystem
sudo mkfs.ext4 -L data /dev/vgdata/lvdata

# Create the mount point
sudo mkdir -p /data

# Change ownership of the mount point to your user
# Replace 'your_username' with your actual username
sudo chown -R your_username /data

# Add the new filesystem to /etc/fstab for automatic mounting on boot
UUID=$(sudo blkid -s UUID -o value /dev/vgdata/lvdata)
echo "UUID=$UUID /data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

# Reload systemd and mount the new filesystem
sudo systemctl daemon-reload
sudo mount -a
```

---

## Step 2: Install Command-Line Tools on Jumphost

Install the required OpenShift command-line tools on the **jumphost**.

### Install OpenShift and Kubernetes Clients (`oc` & `kubectl`)

1.  Navigate to the data directory.
    ```
    cd /data
    ```
2.  Download the latest stable OpenShift client for Linux.
    ```
    curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
    ```
3.  Extract the archive and move the binaries to your system's PATH.
    ```
    tar -xvf openshift-client-linux.tar.gz
    sudo mv oc kubectl /usr/bin/
    ```

### Install the OpenShift Mirroring Tool (`oc-mirror`)

1.  Download and extract the `oc-mirror` tool.
    ```
    curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/oc-mirror.rhel9.tar.gz
    tar -xvf oc-mirror.rhel9.tar.gz
    ```
2.  Move the binary to your system's PATH and verify the installation.
    ```
    sudo mv oc-mirror /usr/bin/
    oc-mirror version
    ```

---

## Step 3: Mirror OpenShift Container Images

For an air-gapped installation, you must first mirror the required container images to a local registry accessible by the cluster.

### Define the Image Set

The `oc-mirror` tool uses an `imageset-config.yaml` file to determine which OpenShift version and operator images to mirror. The configuration files for this guide are stored in a Git repository that should be cloned into the `/data` directory on your jumphost.

Example configuration files:

- [`ocp/oc-mirror/isc.yaml`](ocp/oc-mirror/isc.yaml): Base OpenShift images.
- [`ocp/oc-mirror/isc-additional.yaml`](ocp/oc-mirror/isc-additional.yaml): Additional operator images.

### Mirror Images to a Local Directory

Run the `oc-mirror` command to download the images specified in your configuration. This command packages the images into a tarball in the `/data/mirror` directory. This step simulates downloading assets on an internet-connected machine before transferring them to the disconnected environment.

```
oc-mirror --config=/data/infrakvm/ocp/oc-mirror/isc.yaml file:///data/mirror/
```

### Push Images to the Local Quay Registry

Your environment includes a pre-configured Quay container registry. You will push the mirrored images to this registry to make them accessible to your OpenShift cluster during installation.

1.  Log in to your assigned Quay registry using the provided credentials.

    - https://quay.kubernetes.day
    - https://quay2.kubernetes.day

2.  Push the images from your local tarball to the Quay registry. Replace `your_quay_username` with the username provided to you.
    ```
    oc-mirror --from=/data/mirror/ docker://quay.kubernetes.day/your_quay_username/ocp4.19/
    ```

### Review Generated Manifests

After the mirroring process completes, `oc-mirror` generates several Kubernetes manifest files that are required to configure your cluster to use the local registry.

- **Location:** The generated resources are located in the `working-dir/cluster-resources` subdirectory within your mirror path (e.g., `/data/mirror/working-dir/cluster-resources`).
- **Contents:** This directory includes essential manifests like `ImageDigestMirrorSet` (IDMS) and `CatalogSource` files. These must be applied to your OpenShift cluster after its initial deployment.

  ![oc-mirror result](images/2025-11-12%2000.49.22@2x.png)

  > 💡 **Tip:** If the mirroring process fails, review the error logs. Many common issues can be resolved by simply retrying the `oc-mirror` command.

---

## Step 4. Create Installation Configuration Files

Now that you've prepared the infrastructure and mirrored the necessary container images, the next stage of the agent-based installation is to create the configuration files that the installer will use to generate a bootable ISO. This ISO will then be used to deploy your OpenShift cluster.

This process involves two key files:

- `install-config.yaml`: Defines the overall cluster configuration, including networking, the pull secret for your local registry, and the base domain.
- `agent-config.yaml`: Specifies the network configuration for each of the cluster nodes (masters and workers).

On your jumphost, create a directory to hold your installation configuration files. It's a good practice to keep these organized.

```
mkdir -p /data/ocp
cd /data/ocp
```

1. Create [`install-config-vsphere.yaml`](ocp/install-config-vsphere.yaml)

   This file tells the OpenShift installer how to build your cluster. You will need to customize it with details from your environment, such as your pull secret and the location of your mirrored images.

   Use the provided [`install-config-vsphere.yaml`](ocp/install-config-vsphere.yaml). You must replace the placeholder values with your specific information.

2. Create [`agent-config.yaml`](ocp/agent-config.yaml)

   This file provides the agent with the specific network configuration for each node in your cluster, including IP addresses, MAC addresses, and hostnames. One of the master nodes will be designated as the "rendezvous host", which is the node that orchestrates the installation process.

   Use the provided [`agent-config.yaml`](ocp/agent-config.yaml). Make sure to use the MAC addresses and assign static IPs for each of your master and worker VMs. The rendezvousIP should be the IP address of your first master node. You must replace the placeholder values with your specific information.

---

## Step 5: Generate the Agent Boot ISO

With your configuration files in place, you can now generate the bootable ISO image.

Run the following command from within your `/data/ocp` directory:

```
openshift-install agent create image --dir .
```

This command will validate your configuration files and create an `agent.x86_64.iso` file.
