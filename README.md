

# Setup Infra Requirements
1. https://docs.docker.com/engine/install/rhel/
2. https://docs.docker.com/engine/install/linux-postinstall/
3. docker network create lab_nw --driver=bridge   --subnet=172.18.0.0/23 --ip-range=172.18.0.0/23 --gateway=172.18.0.1
4. git clone <thisrepo>/infrakvm
5. cd infrakvm && mkdir -p ./adguard/workdir && mkdir -p ./adguard/confdir
6. docker compose up -d

