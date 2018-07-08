
/*
Copyright (c) 2016, UPMC Enterprises
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name UPMC Enterprises nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL UPMC ENTERPRISES BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PR)
OCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
*/

provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
    enable_dns_hostnames = true

    tags {
        Name = "${var.cluster-name}"
    }
}

resource "aws_internet_gateway" "gw" {
    vpc_id = "${aws_vpc.main.id}"

    tags {
        Name = "${var.cluster-name}"
   }
}

resource "aws_route_table" "r" {
    vpc_id = "${aws_vpc.main.id}"
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.gw.id}"
    }

    depends_on = ["aws_internet_gateway.gw"]

    tags {
        Name = "${var.cluster-name}"
    }
}

resource "aws_route_table_association" "public" {
    subnet_id = "${aws_subnet.public.id}"
    route_table_id = "${aws_route_table.r.id}"
}

resource "aws_subnet" "public" {
    vpc_id = "${aws_vpc.main.id}"
    cidr_block = "10.0.100.0/24"
    availability_zone = "${var.region}a"
    map_public_ip_on_launch = true

    tags {
        Name = "${var.cluster-name}"
    }
}

resource "aws_security_group" "kubernetes" {
  name = "${var.cluster-name}"
  description = "Allow inbound ssh traffic"
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "${var.cluster-name}"
  }
}

resource "aws_security_group_rule" "allow_all_from_self" {
  type            = "ingress"
  from_port       = 0
  to_port         = 0
  protocol        = "-1"
  source_security_group_id = "${aws_security_group.kubernetes.id}"

  security_group_id = "${aws_security_group.kubernetes.id}"
}

resource "aws_security_group_rule" "allow_ssh_from_admin" {
  type            = "ingress"
  from_port       = 22
  to_port         = 22
  protocol        = "tcp"
  cidr_blocks     = "${split(",", var.admin-cidr-blocks)}"

  security_group_id = "${aws_security_group.kubernetes.id}"
}

resource "aws_security_group_rule" "allow_k8s_from_admin" {
  type            = "ingress"
  from_port       = 6443
  to_port         = 6443
  protocol        = "tcp"
  cidr_blocks     = "${split(",", var.admin-cidr-blocks)}"

  security_group_id = "${aws_security_group.kubernetes.id}"
}

resource "aws_security_group_rule" "allow_all_fout" {
  type            = "egress"
  from_port       = 0
  to_port         = 0
  protocol        = "-1"
  cidr_blocks     = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.kubernetes.id}"
}

data "template_file" "master-userdata" {
    template = "${file("master.sh")}"

    vars {
        k8stoken = "${var.k8stoken}"
    }
}

data "template_file" "worker-userdata" {
    template = "${file("worker.sh")}"

    vars {
        k8stoken = "${var.k8stoken}"
        masterIP = "${aws_spot_instance_request.k8s-master.private_ip}"
    }
}

data "aws_ami" "latest_ami" {
  filter {
    name   = "name"
    values = ["ubuntu-minimal/images-testing/hvm-instance/ubuntu-bionic-daily-amd64-minimal-*"]
    # There seem to be only testing minimal images. Check for released versions of ubuntu-minimal/images/hvm-instance/ubuntu-bionic-18.04-amd64-minimal
  }

  most_recent = true
  owners      = ["099720109477"] # Ubuntu
}

resource "aws_iam_role" "role" {
  name = "${var.cluster-name}"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "policy" {
    role       = "${aws_iam_role.role.name}"
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.cluster-name}"
  role = "${aws_iam_role.role.name}"
}

resource "aws_spot_instance_request" "k8s-master" {
  ami           = "${data.aws_ami.latest_ami.id}"
  instance_type = "${var.instance-type}"
  subnet_id = "${aws_subnet.public.id}"
  user_data = "${data.template_file.master-userdata.rendered}"
  key_name = "${var.k8s-ssh-key}"
  iam_instance_profile   = "${aws_iam_instance_profile.profile.name}"
  vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
  spot_price = "0.01"
  valid_until = "9999-12-25T12:00:00Z"
  wait_for_fulfillment = true

  depends_on = ["aws_internet_gateway.gw"]

  tags {
      Name = "${var.cluster-name}-master"
  }
}

# Spot fleet for workers
# This role grants the Spot fleet permission to terminate Spot instances on your behalf when you cancel its Spot fleet request using CancelSpotFleetRequests or when the Spot fleet request expires, if you set terminateInstancesWithExpiration.
resource "aws_iam_policy_attachment" "fleet" {
  name       = "${var.cluster-name}-spot-fleet"
  roles      = ["${aws_iam_role.fleet.name}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetRole"
}
# This role allows tagging of spots
resource "aws_iam_policy_attachment" "fleet-tagging" {
  name       = "${var.cluster-name}-spot-fleet-tagging"
  roles      = ["${aws_iam_role.fleet.name}"]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

resource "aws_iam_role" "fleet" {
  name = "${var.cluster-name}-spot-fleet"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "spotfleet.amazonaws.com",
          "ec2.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_spot_fleet_request" "worker" {
  iam_fleet_role                      = "${aws_iam_role.fleet.arn}"
  target_capacity                     = "${var.worker-count}"
  terminate_instances_with_expiration = true
  replace_unhealthy_instances         = true
  excess_capacity_termination_policy  = "Default" # Terminate instances if the fleet is too big
  valid_until                         = "9999-12-25T12:00:00Z"

  launch_specification {
    ami                    = "${data.aws_ami.latest_ami.id}"
    instance_type          = "${var.instance-type}"
    ebs_optimized          = false
    weighted_capacity      = 1 # Says that this instance type has 1 CPU
    spot_price             = "0.01"
    subnet_id              = "${aws_subnet.public.id}"
    vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
    iam_instance_profile   = "${aws_iam_instance_profile.profile.name}"
    key_name               = "${var.k8s-ssh-key}"
    user_data              = "${data.template_file.worker-userdata.rendered}"
    tags = "${
      map(
       "Name", "${var.cluster-name}-worker",
      )
    }"
  }
  depends_on = ["aws_iam_policy_attachment.fleet"]
}

