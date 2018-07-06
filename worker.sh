#!/bin/bash -v
swapoff -a
sed -i '/swap/d' /etc/fstab

# Install K8S and Kubeadm
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl kubernetes-cni

# Install Docker and point at big ephemeral drive
curl -sSL https://get.docker.com/ | sh
mkdir /mnt/docker
echo 'export DOCKER_OPTS="-g /mnt/docker --log-driver=json-file --log-opt=max-size=10m --log-opt=max-file=5"' >> /etc/default/docker
systemctl start docker

# Pass bridged IPv4 traffic to iptables chains (required by Flannel)
echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/60-flannel.conf
service procps start

# Join the cluster
for i in {1..50}; do kubeadm join --token=${k8stoken} --discovery-token-unsafe-skip-ca-verification ${masterIP}:6443 && break || sleep 15; done
