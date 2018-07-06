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

# Install Docker, point at big ephemeral drive and turn on log rotation
curl -sSL https://get.docker.com/ | sh
mkdir /mnt/docker
echo 'export DOCKER_OPTS="-g /mnt/docker --log-driver=json-file --log-opt=max-size=10m --log-opt=max-file=5"' >> /etc/default/docker
systemctl start docker

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
