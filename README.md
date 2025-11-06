# Setup Infra Requirements
Prepared for Haseem / Sylvia. We're going to prepare infrastructure requirements from scratch, and make this a disconnected cluster.
- tailscale (your personal VPN)
- DNS server
- DHCP server

## Get your IBM Cloud environment up and create your own jumphost (bastion)
In customer's environment, there could be RHEL / Ubuntu or other Linux distributions. We're not going to harp on which distro is the jumphost here. Let's start and login to **VMware Cloud**,
1. Create your Jumphost VM (Ubuntu) with 8 vCPU, 12GB of RAM, 50GB of storage space. This should take around 10-15 minutes. Feel free to follow the video guide, https://share.cleanshot.com/F3M1TQyw

    - workload_share_FZZZD > ubuntu-24.04.3-desktop-amd64.iso
    ![alt text](images/2025-11-07%2002.44.53@2x.png)


    - VM Settings
    ![alt text](images/2025-11-07%2002.45.50@2x.png)


1. Install **docker**, since we're using Ubuntu, follow this guide:

    - https://docs.docker.com/engine/install/ubuntu/
    - https://docs.docker.com/engine/install/linux-postinstall/

    If you encounter issue installing docker, skip & follow step 2.

2. Clone the repository

        git clone https://github.com/explicitworkload/infrakvm.git

        cd infrakvm && mkdir -p ./adguard/workdir && mkdir -p ./adguard/confdir

        chown -R <username>:docker ./adguard

        chmod -R u+rwX,g+rwX ./adguard
    
    .

    (skip this step if your docker installation is successful. press <em>Enter</em> when prompted to create docker baseline policy.)

        chmod +x ./scripts/install-docker.sh
        ./scripts/install-docker.sh
        
    .

    **(continue from this step, to disable ubuntu's default DNS systemresolved)**

        chmod +x ./scripts/ubuntu-disableresolved.sh
        ./scripts/ubuntu-disableresolved.sh

2. Let's install DNS & DHCP server:
    
        docker compose up -d

    Open the setup page of AdGuardHome http://192.168.28.11:3000/install.html 



2. Install **tailscale** on **bastion**, https://www.tailscale.com

    At the final step of installation, you need to authenticate your machine with tailscale to complete installation.
    
    Next, run the following in terminal to enable you to access your bastion from your laptop directly. Change the value <em>192.168.x.0</em> to your private network given on the demo environment details.

        tailscale up --advertise-exit-nodes --advertise-routes=192.168.x.0/24
    

3. Install **tailscale** on your laptop, once installation is complete, check:

        tailscale status

    (it should look similar to the following)

        [lab-user@bastion-zrphd infrakvm]$ tailscale status
        100.60.0.1      bastion-zrphd         bastion.bncnbc.ts.net  linux    -
        100.60.0.2      jgoh-mac              tagged-devices         macOS    -

        # Health check:
        #     - Some peers are advertising routes but --accept-routes is false
        [lab-user@bastion-zrphd infrakvm]$


4. Edit /etc/chronyc.conf in **bastion**, add in a good ntp source. Always have a good NTP source.

    Add the following into /etc/chronyc.conf. using sudo.

        pool time.google.com iburst
        pool time.cloudflare.com iburst
    ![alt text](images/2025-11-07%2002.02.11@2x.png "ntp")

    save and restart chronyd.

        sudo systemctl restart chronyd

    check chronyc has reached the right ntp sources

        chronyc tracking
        chronyc sources -v
    
    ![alt text](images/2025-11-07%2002.06.32@2x.png "chronyc")

5. Verify: You should be able to ping your **bastion** (192.168.28.10) from your laptop now.

        ping bastion-xxxxx
        ping 192.168.28.10
        tailscale ping bastion-xxxxx

