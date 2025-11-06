# Setup Infra Requirements
Prepared for Haseem / Sylvia. We're going to prepare infrastructure requirements from scratch, and make this a disconnected cluster. To start off, the steps below will guide you to setup a jumphost (bastion), within it will also contain the following software packages. 

- Tailscale (VPN)
- DNS server based on AdGuard Home, we will block all DNS internet queries to mimick a airgapped environment.

These steps will take around 1-2 hours.

## Get your IBM Cloud environment up and create your own jumphost (bastion)
Let's start and login to **VMware Cloud**, feel free to follow the video guide, https://share.cleanshot.com/F3M1TQyw
1. Create your Jumphost VM (Ubuntu) with 8 vCPU, 12GB of RAM, 50GB of storage space. This should take around 10-15 minutes. 

    - workload_share_FZZZD > ubuntu-24.04.3-desktop-amd64.iso
    ![alt text](images/2025-11-07%2002.44.53@2x.png)


    - VM Settings
    ![alt text](images/2025-11-07%2002.45.50@2x.png)

    .
1. Install **docker**, since we're using Ubuntu, follow this guide:

    - https://docs.docker.com/engine/install/ubuntu/
    - https://docs.docker.com/engine/install/linux-postinstall/

    <em>If you encounter issue installing docker, skip this step and use my automation script to setup docker.</em>

    .

2. Clone the repository. Take note replace <username> with your ubuntu account username.

        git clone https://github.com/explicitworkload/infrakvm.git

        cd infrakvm

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

    .

2. Install **tailscale** on **jumphost** https://www.tailscale.com

    At the final step of installation, you need to authenticate & approve your machine in tailscale web console to complete the installation. Try to figure this part out, if not reach out to me.

    Once installation is complete, check:

        tailscale status

    (it should look similar to the following)

        [lab-user@bastion-zrphd infrakvm]$ tailscale status
        100.60.0.1      bastion-zrphd         bastion.bncnbc.ts.net  linux    -
        100.60.0.2      jgoh-mac              tagged-devices         macOS    -

        # Health check:
        #     - Some peers are advertising routes but --accept-routes is false
        [lab-user@bastion-zrphd infrakvm]$

    
    Next, run the following ONLY in the jumphost terminal to enable you to access your jumphost from your laptop directly. Change the value <em>192.168.x.0</em> to your private network given on the demo environment details.

        sudo tailscale up --advertise-exit-nodes --advertise-routes=192.168.x.0/24
    
    .
3. Install **tailscale** on your laptop, once installation is complete, check:

        tailscale status
    .
2. Next, let's install the DNS service. I have scripted most parts, but intentionally kept this step so you know how to start the service again.
    
        docker compose up -d

5. Now, let's configure the DNS services. Open the setup page of AdGuardHome from your laptop, http://192.168.28.11/ (this is the IP of your jumphost)

    * username: admin
    * password: P@$$w0rd1!

    Go to Filters -> DNS Rewrites, modify all entries following your environment.

    ![alt text](images/2025-11-07%2004.21.52@2x.png)

    We will come back to this again when we start setting up OpenShift later.

    .

4. Login to https://login.tailscale.com/admin/dns and add custom nameserver, under "DNS" in the navigation bar. Follow the image and replace the domain with your environment domain.

    ![alt text](images/2025-11-07%2004.38.08@2x.png)
    You should replace 192.168.28.11 with your jumphost IP.
    
    .


4. Update NTP for the jumphost. Edit /etc/chronyc.conf in **jumphost**, add in a good ntp source. Always have a good NTP source.

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
    .

5. Verify: You should be able to ping your **jumphost** (192.168.28.10) from your laptop now.

        ping bastion-xxxxx
        ping 192.168.28.10
        tailscale ping bastion-xxxxx

    .
6. Done. Good job.