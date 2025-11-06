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

2. Let's install DNS & DHCP server:

        git clone https://github.com/explicitworkload/infrakvm.git

        cd infrakvm && mkdir -p ./adguard/workdir && mkdir -p ./adguard/confdir

        chmod +x ./scripts/ubuntu-disableresolved.sh

        ./scripts/ubuntu-disableresolved.sh

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

5. Next, add firewall rich rules to allow only the 192.168.28.0/24 subnet access. <em>Remember to replace 192.168.x.0/24 with your demo environment's CIDR range.</em>

        sudo su -

    Add rich rules to allow only from 192.168.28.0/24 subnet:

        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.28.0/24 port port=53 protocol=tcp accept'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.28.0/24 port port=53 protocol=udp accept'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.28.0/24 port port=67 protocol=udp accept'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.28.0/24 port port=68 protocol=udp accept'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.28.0/24 port port=80 protocol=tcp accept'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.28.0/24 port port=443 protocol=tcp accept'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.28.0/24 port port=443 protocol=udp accept'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.28.0/24 port port=3000 protocol=tcp accept'

    Add rich rules to reject access from other IPs on those ports:
    
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=53 protocol=tcp drop'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=53 protocol=udp drop'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=67 protocol=udp drop'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=68 protocol=udp drop'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=80 protocol=tcp drop'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=443 protocol=tcp drop'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=443 protocol=udp drop'
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 port port=3000 protocol=tcp drop'

    Allow ping from your LAN only (192.168.28.0/24) 

        # Allow ICMP echo-request from 192.168.28.0/24
        firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.28.0/24 icmp-type name="echo-request" accept'


    Reload firewalld to apply changes, and exit from root:

        firewall-cmd --reload && exit

    Verify: You should be able to ping your **bastion** (192.168.28.10) from your laptop now.

        ping bastion-xxxxx
        ping 192.168.28.10
        tailscale ping bastion-xxxxx