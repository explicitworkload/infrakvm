# Setup Infra Requirements
We're going to prepare infrastructure requirements from scratch, and make this a disconnected cluster.
- tailscale (your personal VPN)
- DNS server
- DHCP server

## Get your IBM Cloud environment up and set these up on bastion
Login to **bastion**
1. git clone https://github.com/explicitworkload/infrakvm.git

        cd infrakvm && mkdir -p ./adguard/workdir && mkdir -p ./adguard/confdir

        docker network create lab_nw --driver=bridge   --subnet=172.18.0.0/23 --ip-range=172.18.0.0/23 --gateway=172.18.0.1
    
        docker compose up -d

2. Install **tailscale** on **bastion**

    After installation completes, run the following in terminal,

        tailscale up --advertise-exit-nodes --advertise-routes=192.168.x.0/24
    
    <em>(change 192.168.x.0 to your private network given on the demo environment)</em>

3. Install **tailscale** on your laptop, once installation is complete, check:

        tailscale status

    (it should look similar to the following)

        [lab-user@bastion-zrphd infrakvm]$ tailscale status
        100.60.0.1      bastion-zrphd         bastion.bncnbc.ts.net  linux    -
        100.60.0.2      jgoh-mac              tagged-devices         macOS    -

        # Health check:
        #     - Some peers are advertising routes but --accept-routes is false
        [lab-user@bastion-zrphd infrakvm]$

        

3. Install **docker**, since we're using RHEL, follow this guide:

    - https://docs.docker.com/engine/install/rhel/
    - https://docs.docker.com/engine/install/linux-postinstall/

4. on bastion, let's pull from a good ntp source

    add the following into /etc/chronyc.conf. using sudo.

        pool time.google.com iburst
        pool time.cloudflare.com iburst
    ![alt text](images/2025-11-07%2002.02.11@2x.png "ntp")

    save and restart chronyd.

        sudo systemctl restart chronyd

    check chronyc has reached the right ntp sources

        chronyc tracking
        chronyc sources -v
    
    ![alt text](images/2025-11-07%2002.06.32@2x.png) "chronyc")