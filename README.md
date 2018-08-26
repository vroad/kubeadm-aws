## Really cheap Kubernetes cluster on AWS with kubeadm

This repository contains a bunch of Bash and Terraform code which provisions what I believe to be the cheapest possible single master Kubernetes cluster on AWS. You can run a 1 master, 1 worker cluster for somewhere around $6 a month, or just the master node (which can also run pods) for around $3 a month.

To achieve this, it uses m1.small spot instances and the free ephemeral storage they come with instead of EBS volumes.

Current features:

* Automatic backup and recovery. So if your master gets terminated, when the replacement is provisioned by AWS it will pick up where the old one left off without you doing anything. 😁
* Completely automated provisioning through Terraform and Bash.
* Variables for many things including number of workers (requested through spot fleet) and EC2 instance type.
* [External DNS](https://github.com/kubernetes-incubator/external-dns) as a cheap ELB alternative.
* Persistent Volumes using GP2 storage on EBS.

#### _NOTE: Really really don't use this in production! However in theory the reliability should be quite good._

### Run it!

1. Clone the repo
2. [Install Terraform](https://www.terraform.io/intro/getting-started/install.html)
3. Generate token: `python -c 'import random; print "%0x.%0x" % (random.SystemRandom().getrandbits(3*8), random.SystemRandom().getrandbits(8*8))' > token.txt`
4. Make an SSH key on us-east-1 from the AWS console
5. Run terraform plan: `terraform plan -var k8s-ssh-key=<aws-ssh-key-name> -var k8stoken=$(cat token.txt) -var admin-cidr-blocks="<my-public-ip-address>/32"`
6. Build out infrastructure: `terraform apply -var k8s-ssh-key=<aws-ssh-key-name> -var k8stoken=$(cat token.txt) -var admin-cidr-blocks="<my-public-ip-address>/32"`
7. SSH to K8S master and run something: `ssh ubuntu@$(terraform output master_dns) -i <aws-ssh-key-name>.pem kubectl get no`
10. Done!

Optional Variables:

* `worker-count` - How many worker nodes to request via Spot Fleet (1 by default)
* `region` - Which AWS region to use (us-east-1 by default)
* `kubernetes-version` - Which Kubernetes/kubeadm version to install (1.11.2 by default)
* `instance-type` - Which EC2 instance type to use (m1.small by default)
* `cluster-name` - Used for naming the created AWS resources (k8s by default)
* `backup-enabled` - Set to "0" to disable the automatic backups ("1" by default)
* `external-dns-enabled` - Set to "0" to disable the pre-requisites for ExternalDNS ("1" by default)

### TODO

* Find a reliable way of generating tokens. [See this issue.](https://github.com/upmc-enterprises/kubeadm-aws/issues/11)
* Improve security: Leaving the token valid forever probably isn't the best idea.
* Alerting about when hosts are terminated.
* General logging and monitoring of Kubernetes and running apps.
* Terraform remote state on S3.

