##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}

variable "name" {
  default = "AMIS-TF"
}

variable "key_name" {
  default = "AMIS"
}

variable "image_id" {
  default = "ami-07683a44e80cd32c5"
}

variable "ip_address_test_pc" {
  default = "86.88.108.53"
}

variable "cidr_block" {
  default = "10.0.0.0/16"
}

variable "azs" {
  default = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "eu-west-1"
}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "${var.name}-VPC"

  cidr            = "${var.cidr_block}"
  azs             = "${var.azs}" 
  public_subnets = ["${cidrsubnet(var.cidr_block, 8, 1)}",
                    "${cidrsubnet(var.cidr_block, 8, 2)}",
                    "${cidrsubnet(var.cidr_block, 8, 3)}"]
  private_subnets = ["${cidrsubnet(var.cidr_block, 8, 4)}",
                     "${cidrsubnet(var.cidr_block, 8, 5)}",
                     "${cidrsubnet(var.cidr_block, 8, 6)}"]

  enable_nat_gateway = true
  single_nat_gateway = false

  create_database_subnet_group = false

  enable_dns_hostnames = true
  enable_dns_support = true
}


resource "aws_security_group" "security_group_public" {
  name   = "${var.name}-public-securitygroup"
  vpc_id = "${module.vpc.vpc_id}"
  description = "Enable ssh trafic from own PC, http trafic from world and all outgoing trafic"

  ingress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.ip_address_test_pc}/32"]
    protocol    = "-1"
    description = "Allow all trafic from the test PC"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all http trafic"
  }

  #allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow all"
  }

  tags {
    Name        = "${var.name}-sg-public"
  }
}

resource "aws_security_group" "security_group_private" {
  name   = "${var.name}-private-securitygroup"
  vpc_id = "${module.vpc.vpc_id}"
  description = "Enable all trafic from internal network"

  ingress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["10.0.0.0/16"]
    protocol    = "-1"
    description = "Allow all trafic from within this network"
  }

  egress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
    description = "Allow all"
  }

  tags {
    Name        = "${var.name}-sg-public"
  }
}

resource "aws_launch_configuration" "launch_configuration_private" {
  name_prefix = "${var.name}-lc-private-"
  image_id = "${var.image_id}"
  instance_type = "t2.micro"
  key_name = "${var.key_name}"
  security_groups = ["${aws_security_group.security_group_private.id}"] 
  user_data = <<EOF
#!/bin/bash
yum install httpd -y
systemctl start httpd
echo '<p>Background info</p>' > /var/www/html/index.html
EOF
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "loadbalancer_private" {
  name = "${var.name}-lb-pvt"

  subnets         = ["${module.vpc.private_subnets}"]
  security_groups = ["${aws_security_group.security_group_private.id}"]
  internal        = "true"

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags {
    Name        = "${var.name}-lb-pvt"
  }
}

resource "aws_autoscaling_group" "autoscaling_group_private" {
  name = "${var.name}-asg-pvt"
  load_balancers = ["${aws_elb.loadbalancer_private.id}"]
  launch_configuration = "${aws_launch_configuration.launch_configuration_private.id}"
  desired_capacity = 3
  min_size = 2
  max_size = 6
  health_check_grace_period = 20
  tags {
    key                 = "Name"
    value               = "${var.name}-asg-pvt"
    propagate_at_launch = "true"
  }
  vpc_zone_identifier = ["${module.vpc.private_subnets}"]
  
  depends_on = ["aws_security_group.security_group_public", "module.vpc", "aws_security_group.security_group_private"]
}

resource "aws_launch_configuration" "launch_configuration_public" {
  name_prefix = "${var.name}-lc-pub-"
  image_id = "${var.image_id}"
  instance_type = "t2.micro"
  key_name = "${var.key_name}"
  security_groups = ["${aws_security_group.security_group_public.id}"] 
  user_data = <<EOF
#!/bin/bash
yum install httpd -y
systemctl start httpd
echo '<p>Foreground website</p>' > /var/www/html/index.html
curl ${aws_elb.loadbalancer_private.dns_name} >> /var/www/html/index.html
EOF
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "loadbalancer_public" {
  name = "${var.name}-lb-pub"

  subnets         = ["${module.vpc.public_subnets}"]
  security_groups = ["${aws_security_group.security_group_public.id}"]
  internal        = "false"

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags {
    Name        = "${var.name}-lb-pub"
  }
}

resource "aws_autoscaling_group" "autoscaling_group_public" {
  name = "${var.name}-asg-pub"
  load_balancers = ["${aws_elb.loadbalancer_public.id}"]
  launch_configuration = "${aws_launch_configuration.launch_configuration_public.id}"
  desired_capacity = 3
  min_size = 2
  max_size = 6
  health_check_grace_period = 20
  tags {
    key                 = "Name"
    value               = "${var.name}-asg-pub"
    propagate_at_launch = "true"
  }
  vpc_zone_identifier = ["${module.vpc.public_subnets}"]

  depends_on = ["aws_autoscaling_group.autoscaling_group_private", "aws_security_group.security_group_private", "module.vpc"]
}

###################################################################################
## OUTPUT
###################################################################################

output "aws_elb_public_dns" {
  value = "${aws_elb.loadbalancer_public.dns_name}"
}

