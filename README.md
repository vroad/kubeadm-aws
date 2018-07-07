## Really cheap Kubernetes cluster on AWS with kubeadm

This is a fork of a quick start by UPMC Enterprises. I've adapted (and possibly improved it) to use the cheapest available spot instances to run a 1 master, 1 worker cluster for somewhere around $6 a month. It uses m1.small spot instances and the free ephemeral storage they come with instead of EBS volumes.

### How it works

The terraform script builds out a new VPC in your account and a single subnet (to avoid cross AZ bandwidth charges). It will also provision an internet gateway and setup a routing table to allow internet access.

#### _NOTE: Really really don't use this in production!_

### Run it!

1. Clone the repo
2. [Install Terraform](https://www.terraform.io/intro/getting-started/install.html)
3. Generate token: `python -c 'import random; print "%0x.%0x" % (random.SystemRandom().getrandbits(3*8), random.SystemRandom().getrandbits(8*8))' > token.txt`
4. Make an SSH key on us-east-1 from the AWS console
5. Run terraform plan: `terraform plan -var k8s-ssh-key=<aws-ssh-key-name> -var k8stoken=$(cat token.txt) -var admin-cidr-blocks="<my-public-ip-address>/32"`
6. Build out infrastructure: `terraform apply -var k8s-ssh-key=<aws-ssh-key-name> -var k8stoken=$(cat token.txt) -var admin-cidr-blocks="<my-public-ip-address>/32"`
7. SSH to K8S master and run something: `ssh ubuntu@$(terraform output master_dns) -i <aws-ssh-key-name>.pem kubectl get no`
8. Done!

Optional Variables:

* `worker-count` - How many worker nodes to request via Spot Fleet (1 by default)
* `region` - Which AWS region to use (us-east-1 by default)
* `instance-type` - Which EC2 instance type to use (m1.small by default)

### TODO

* Fix lack of tags on master nodes. Seems to be an issue with plain AWS spot requests
* Generally more flexibility and variables
* Backups
