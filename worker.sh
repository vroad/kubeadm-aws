#!/bin/bash -v
swapoff -a
sed -i '/swap/d' /etc/fstab

# Install K8S, kubeadm and Docker
apt-get update
apt-get dist-upgrade -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

add-apt-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
add-apt-repository "deb https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable"

apt-get update
apt-get install -y kubelet kubeadm kubectl docker-ce

# Point Docker at big ephemeral drive and turn on log rotation
mkdir /mnt/docker
cat <<EOF > /etc/docker/daemon.json
{
    "data-root": "/mnt/docker",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "5"
    }
}
EOF
systemctl restart docker

# Pass bridged IPv4 traffic to iptables chains (required by Flannel)
echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/60-flannel.conf
service procps start

# Join the cluster
for i in {1..50}; do kubeadm join --token=${k8stoken} --discovery-token-unsafe-skip-ca-verification ${masterIP}:6443 && break || sleep 15; done
