#!/bin/bash -ve

# Disable pointless daemons
systemctl stop snapd snapd.socket lxcfs snap.amazon-ssm-agent.amazon-ssm-agent
systemctl disable snapd snapd.socket lxcfs snap.amazon-ssm-agent.amazon-ssm-agent

# Disable swap to make K8S happy
swapoff -a
sed -i '/swap/d' /etc/fstab

# Install K8S, kubeadm and Docker 17.03 (most recent supported version for Kubernetes)
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
export DEBIAN_FRONTEND=noninteractive
apt-get update
wget http://launchpadlibrarian.net/361362020/docker.io_17.03.2-0ubuntu5_amd64.deb
dpkg -i docker.io_17.03.2-0ubuntu5_amd64.deb
apt-get install -fy
apt-get install -y kubelet=${k8sversion}-00 kubeadm=${k8sversion}-00 kubectl=${k8sversion}-00
apt-mark hold kubelet kubeadm kubectl docker.io

# Point Docker at big ephemeral drive and turn on log rotation (messy because data-root option didn't exist in 17.03)
systemctl stop docker
mkdir /mnt/docker
chmod 711 /mnt/docker
rm -rf /var/lib/docker
ln -s /mnt/docker /var/lib/docker
cat <<EOF > /etc/docker/daemon.json
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "5"
    }
}
EOF
systemctl start docker
systemctl enable docker

# Point kubelet at big ephemeral drive
mkdir /mnt/kubelet
echo 'KUBELET_EXTRA_ARGS="--root-dir=/mnt/kubelet --cloud-provider=aws"' > /etc/default/kubelet

# Pass bridged IPv4 traffic to iptables chains (required by Flannel)
echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/60-flannel.conf
service procps start

# Join the cluster
for i in {1..50}; do kubeadm join --token=${k8stoken} --discovery-token-unsafe-skip-ca-verification --node-name=$(hostname -f) ${masterIP}:6443 && break || sleep 15; done
