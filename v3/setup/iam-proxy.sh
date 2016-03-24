#!/bin/bash

# Sets IPTABLES to redirect requests to the AWS metadata service to a container running
# a proxy. This proxy intercepts the request and assumes specific roles depending on the
# label. See: https://github.com/adobe-platform/iam-docker

source /etc/environment

if [ "${NODE_ROLE}" != "worker" ]; then
    exit 0
fi

# First, setup a service to run the proxy

mkdir -p /etc/services
IAM_PROXY_SERVICE_FILE=/etc/services/iam-proxy@.service

cat > $IAM_PROXY_SERVICE_FILE <<EOF
[Unit]
Description=IAMProxy @ %i
After=docker.service bootstrap.service
Requires=docker.service bootstrap.service

[Service]
Environment="IMAGE=etcdctl get /images/iam-proxy"
EnvironmentFile=/etc/environment

User=core
Restart=always
RestartSec=20
TimeoutStartSec=0

ExecStartPre=/usr/bin/sh -c "docker pull $($IMAGE)"
ExecStartPre=-/usr/bin/docker kill iam_proxy
ExecStartPre=-/usr/bin/docker rm iam_proxy

ExecStart=/usr/bin/sh -c "/usr/bin/docker run \
  --name=iam_proxy \
  --volume /var/run/docker.sock:/var/run/docker.sock \
  --restart=always \
  --net=host \
  $($IMAGE)

ExecStop=-/usr/bin/docker stop iam_proxy

[Install]
WantedBy=multi-user.target

[X-Fleet]
Global=false
MachineMetadata=role=worker
MachineMetadata=ip=%i
EOF

chown root:root $IAM_PROXY_SERVICE_FILE
chmod 0644 $IAM_PROXY_SERVICE_FILE

sudo fleetctl submit "${IAM_PROXY_SERVICE_FILE}"
sudo fleetctl start "${iam-proxy%.service}${COREOS_PRIVATE_IPV4}"

# Next, update IPTABLES to route IAM requests to the newly launched service

export NETWORK="bridge"
export GATEWAY="$(ifconfig docker0 | grep "inet " | awk -F: '{print $1}' | awk '{print $2}')"
export INTERFACE="docker0"

# These will not work until Docker > 1.9 is running
#export GATEWAY="$(docker network inspect "$NETWORK" | grep Gateway | cut -d '"' -f 4)"
#export INTERFACE="br-$(docker network inspect "$NETWORK" | grep Id | cut -d '"' -f 4 | head -c 12)"

sudo iptables -t nat -I PREROUTING -p tcp -d 169.254.169.254 --dport 80 -j DNAT --to-destination "$GATEWAY":8080 -i "$INTERFACE"