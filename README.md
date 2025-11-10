# Jumphost Infrastructure Setup (InfraKVM)

**Prepared for:** Haseem / Sylvia / LC / Siyu / Jingwen <br>
**Objective:** Build the base infrastructure for a **disconnected OpenShift cluster** from scratch.

## Overview

This guide walks through the creation of a **jumphost (bastion)** for a disconnected cluster environment.

We'll begin by setting up a **jumphost (bastion)** that will include:

- 🛜 **Tailscale:** A zero-config VPN to provide secure and direct access to the jumphost and its advertised networks from your personal machine.

- 🧩 **AdGuard Home:** A network-wide DNS sinkhole that will act as our local DNS server, blocking outside queries to simulate an air-gapped environment.

⏱ **Estimated duration:** 60-120 minutes.
💡 **Tip:** Keep this guide handy; you’ll return to it later during the OpenShift setup.

### Prerequisites

- Access to the **VMware Cloud** environment (get it from Red Hat Demo Catalog)
- A **Personal Google account** for authenticating with Tailscale.
- Your assigned **private network range** (e.g., `192.168.x.0/24`).

Enjoy!

## Step 1: Create and Prepare the Jumphost VM

First, create the Ubuntu virtual machine that will serve as the jumphost.

1.  **Log in to VMware Cloud** and begin provisioning a new VM with the following specifications:

    - **vCPU:** 8
    - **RAM:** 12 GB
    - **Storage:** 50 GB (Ubuntu root)
    - **Storage 2:** 1024 GB (/data)
    - **OS Image:** Select the `ubuntu-24.04.3-desktop-amd64.iso` located in the `workload_share_FZZZD` content library.

    ![VM Creation](images/2025-11-07%2002.44.53@2x.png)
    ![VM Settings](images/2025-11-07%2002.45.50@2x.png)

2.  **Complete the Ubuntu Installation.** Once the VM is running, perform a standard Ubuntu installation.

3.  **Update the System.** After the installation finishes and you have logged in, open a terminal and run the following commands to ensure all packages are up to date:

    ```
    sudo apt update
    sudo apt upgrade -y
    ```

📺 Follow the video walkthrough: [https://share.cleanshot.com/F3M1TQyw](https://share.cleanshot.com/F3M1TQyw)

---

## Step 2: Disable `systemd-resolved`

Ubuntu's default DNS service, `systemd-resolved`, occupies port 53. This will conflict with AdGuard Home. You must disable it _before_ setting up the DNS container.

1.  **Clone the repository:**

    ```
    git clone https://github.com/explicitworkload/infrakvm.git
    cd infrakvm
    ```

2.  **Run the script** to disable and stop the service:

    ```
    chmod +x ./scripts/ubuntu-disableresolved.sh
    sudo ./scripts/ubuntu-disableresolved.sh
    ```

    This script will reconfigure `NetworkManager` to use a different resolver and free up TCP/UDP port 53.

3.  **Verify:** Confirm that no service is listening on port 53. The command should produce no output.
    ```
    sudo lsof -i :53
    ```

---

## Step 3. Install Docker

Now, install Docker, which is required to run AdGuard Home. Since this is Ubuntu, follow the official Docker installation guides:

1.  **Follow the official Docker guide** to install Docker Engine on Ubuntu:

    - [Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)

2.  **Perform post-installation steps** to manage Docker as a non-root user. This is critical for usability.

    - [Linux post-installation steps for Docker Engine](https://docs.docker.com/engine/install/linux-postinstall/)

> 💬 **Note:**  
> If Docker installation fails, use Step 3 that automates the installation.

3.  **(Optional) Use Fallback Script:** If you encounter any issues with the manual installation, the repository includes an automation script.

    ```
    chmod +x ./scripts/install-docker.sh
    sudo ./scripts/install-docker.sh
    ```

4.  **Verify Installation:** Check that Docker is running correctly. You may need to logout and login to your SSH session again.
    ```
    docker --version
    docker ps
    ```

---

## Step 4: Deploy and Configure AdGuard Home

With Docker ready, deploy AdGuard Home using the provided `docker-compose.yml`.

1.  **Set correct permissions** for the AdGuard configuration directory. Replace `$USER` with your username if the variable is not set correctly.

    ```
    sudo chown -R $USER:docker ./adguard
    chmod -R u+rwX,g+rwX ./adguard
    ```

2.  **Launch the service:**

    ```
    docker network create lab_nw --driver=bridge   --subnet=172.18.0.0/23 --ip-range=172.18.0.0/23 --gateway=172.18.0.1
    docker compose up -d
    ```

3.  **Complete the AdGuard Setup:**

    - 💡 Credentials: admin // P@$$w0rd1
    - Open a browser on your laptop and navigate to `http://<JUMPHOST_IP>:81`, replacing `<JUMPHOST_IP>` with your VM's private IP address (e.g., `192.168.28.11`).
    - On the "Welcome" screen, set the **Admin Web Interface** to listen on `All interfaces` and the **DNS server** to listen on your jumphost's private IP.
    - When prompted, create a secure **username** and **password**. Do not use the example password from the old guide.
    - Log in, navigate to **Filters → DNS Rewrites**, and modify the entries to match your environment's domain and IP addresses.

    ![alt text](images/2025-11-07%2004.21.52@2x.png)

---

## Step 5. Configure Network Access with Tailscale

Install Tailscale on both the jumphost and your laptop to create a secure overlay network.

1.  **Install Tailscale on the Jumphost.** Follow the official installation instructions. During the final step, authenticate in your browser using your Google account.

    ```bash
    curl -fsSL https://tailscale.com/install.sh | sh
    ```

2.  **Advertise Routes from Jumphost:** Run the following command on the **jumphost** to advertise its local private network to your other Tailscale devices.

    - **Important:** Replace `192.168.x.0/24` with the actual private subnet for your environment.

    ```
    sudo tailscale up --advertise-routes=192.168.x.0/24 --advertise-exit-nodes --reset
    ```

3.  **Install Tailscale on Your Laptop.** Install the appropriate client for your OS and log in.

4.  **Approve the Routes:**

    - Go to the [**Machines** page](https://login.tailscale.com/admin/machines) in the Tailscale admin console.
    - Find your jumphost, click the three-dot menu, and select **Edit route settings...**.
    - Approve the subnet route & exit node you advertised.

5.  **Verify Status:** On both machines, run `tailscale status` to see your connected devices.

    It should look similar to the following:

        [lab-user@bastion-zrphd infrakvm]$ tailscale status
        100.60.0.1      bastion-zrphd         bastion.bncnbc.ts.net  linux    -
        100.60.0.2      jgoh-mac              tagged-devices         macOS    -

        # Health check:
        #     - Some peers are advertising routes but --accept-routes is false
        [lab-user@bastion-zrphd infrakvm]$

## Step 6: Link AdGuard to Tailscale DNS

Configure Tailscale to use your new AdGuard server for DNS resolution within your private network.

1.  Navigate to the [**DNS page**](https://login.tailscale.com/admin/dns) in the Tailscale admin console.
2.  Under **Nameservers**, select **Add nameserver** and choose **Custom**.
3.  Enter the **private IP address** of your jumphost (e.g., `192.168.28.11`).
4.  Specify **Domain** as per your environment FQDN (e.g., zrphd.dynamic.redhatworkshops.io).

    ![alt text](images/2025-11-07%2004.38.08@2x.png)

5.  Save

## Step 7: Configure NTP

Ensure the jumphost maintains accurate time by pointing it to reliable NTP sources.

1.  Edit `/etc/chrony/chrony.conf` with `sudo`:

    ```
    sudo nano /etc/chrony/chrony.conf
    ```

2.  **Add** the following lines to the file, and comment out the default (see image)

    ```
    pool time.google.com iburst
    pool time.cloudflare.com iburst
    ```

    ![alt text](images/2025-11-07%2002.02.11@2x.png "ntp")

3.  **Restart and verify `chronyd`:**
    ```
    sudo systemctl restart chronyd
    chronyc tracking
    chronyc sources -v
    ```
    The output should show the new sources and indicate that the time is being synchronized.
    ![alt text](images/2025-11-07%2002.06.32@2x.png "chronyc")

---

## Final Verification

You have now completed the setup. From your laptop, verify that all components are working together:

1.  **Ping the jumphost** via its Tailscale name and private IP:

    ```
    tailscale ping <JUMPHOST_NAME>
    ping <JUMPHOST_PRIVATE_IP>
    ```

2.  **Test DNS resolution** using `dig`. The first command should resolve to your internal IP via AdGuard, and the second should resolve, and the third should pass now but fail later (as per the air-gap goal):

    ```
    dig api.zrphd.dynamic.redhatworkshops.io @<JUMPHOST_PRIVATE_IP>
    dig google.com @<JUMPHOST_PRIVATE_IP>
    dig redhat.io @<JUMPHOST_PRIVATE_IP>
    ```

## Good job. You are now ready to proceed to the next stage.

Let's go, click > [OpenShift.md](OpenShift.md)
