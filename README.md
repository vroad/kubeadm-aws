## Really cheap Kubernetes cluster on AWS with kubeadm

This is a fork of a quick start by UPMC Enterprises. I've adapted (and possibly improved it) to use the cheapest available spot instances amongst other things, to make a really low cost cluster possible. For example you can run a 1 master, 1 worker cluster for somewhere around $6 a month. It uses m1.small spot instances and the free ephemeral storage they come with instead of EBS volumes.

Current features:

* Completely automated provisioning through Terraform of a single master cluster.
* Variables for many things including number of workers (requests through spot fleet) and EC2 instance type.
* Automatic backup and recovery. So if your master gets terminated, when the replacement is provisioned by AWS it will pick up where the old one left off without you doing anything. 😁

#### _NOTE: Really really don't use this in production! However in theory the reliability should be quite good._

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
* `cluster-name` - Used for naming the created AWS resources (k8s by default)
* `backup-enabled` - Set to "0" to disable the automatic backups and creation of the S3 bucket ("1" by default)

### TODO

* Find a reliable way of generating tokens. [See this issue.](https://github.com/upmc-enterprises/kubeadm-aws/issues/11)
* Improve security: Leaving the token valid forever probably isn't the best idea.
* EBS persistent volumes including adding the necessary permissions to the instance profile.
* Alerting about when hosts are terminated.
* General logging and monitoring of Kubernetes and running apps.
* Make the Kubernetes version a variable rather than just grabbing the latest.

