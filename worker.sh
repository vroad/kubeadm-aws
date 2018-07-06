#!/bin/bash -v
swapoff -a
sed -i '/swap/d' /etc/fstab

curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl kubernetes-cni
curl -sSL https://get.docker.com/ | sh
systemctl start docker

# Pass bridged IPv4 traffic to iptables chains (required by Flannel)
echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/60-flannel.conf
service procps start

for i in {1..50}; do kubeadm join --token=${k8stoken} --discovery-token-unsafe-skip-ca-verification ${masterIP}:6443 && break || sleep 15; done
