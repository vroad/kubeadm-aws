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

# Set up the cluster
kubeadm init --token=${k8stoken} --pod-network-cidr=10.244.0.0/16

# Pass bridged IPv4 traffic to iptables chains (required by Flannel like the above cidr setting)
echo "net.bridge.bridge-nf-call-iptables = 1" > /etc/sysctl.d/60-flannel.conf
service procps start

# Set up kubectl for the ubuntu user and Flannel
mkdir -p /home/ubuntu/.kube && cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config && chown -R ubuntu. /home/ubuntu/.kube
su -c 'kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml' ubuntu

# Allow pod scheduling on the master (no recommended but we're doing it anyway :D)
su -c 'kubectl taint nodes --all node-role.kubernetes.io/master-' ubuntu
