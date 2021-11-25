##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}

variable "name" {
  default = "AMIS-CF"
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

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "eu-west-1"
}

##################################################################################
# DATA
##################################################################################

data "aws_availability_zones" "available" {}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
resource "aws_vpc" "vpc" {
  cidr_block = "${var.cidr_block}"

  tags {
    Name        = "${var.name}-VPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name        = "${var.name}-internetgateway"
  }
}

resource "aws_subnet" "publicsubnet" {
  count                   = "${length(data.aws_availability_zones.available.names)}"
  cidr_block              = "${cidrsubnet(var.cidr_block, 8, count.index + 1)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  map_public_ip_on_launch = "true"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"

  tags {
    Name        = "${var.name}-subnet-${count.index + 1}-public"
  }
}

resource "aws_subnet" "privatesubnet" {
  count                   = "${length(data.aws_availability_zones.available.names)}"
  cidr_block              = "${cidrsubnet(var.cidr_block, 8, count.index + 4)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  map_public_ip_on_launch = "false"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"

  tags {
    Name        = "${var.name}-subnet-${count.index + 1}-private"
  }
}

resource "aws_eip" "ip_for_nat_gateway" {
  count                   = "${length(data.aws_availability_zones.available.names)}"
  vpc                     = "true"
  tags {
    Name                  = "${var.name}-eip-${count.index+1}"
  }
}

resource "aws_nat_gateway" "natgateway" {
  count                   = "${length(data.aws_availability_zones.available.names)}"
  allocation_id           = "${element(aws_eip.ip_for_nat_gateway.*.id, count.index)}"
  subnet_id               = "${element(aws_subnet.publicsubnet.*.id, count.index)}"
  tags {
    Name                  = "${var.name}-natgateway-${count.index+1}"
  }
}

resource "aws_route_table" "public_subnet_route_table" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags {
    Name        = "${var.name}-public-subnet-routetable"
  }
}

resource "aws_route_table_association" "subnet_public_route_table_association" {
  count          = "${length(data.aws_availability_zones.available.names)}"

  subnet_id      = "${element(aws_subnet.publicsubnet.*.id,count.index)}"
  route_table_id = "${aws_route_table.public_subnet_route_table.id}"
}

resource "aws_route_table" "private_subnet_route_table" {
  count          = "${length(data.aws_availability_zones.available.names)}"
  
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${element(aws_nat_gateway.natgateway.*.id, count.index)}"
  }

  tags {
    Name        = "${var.name}-private-subnet-routetable"
  }
}

resource "aws_route_table_association" "subnet_private_route_table_association" {
  count          = "${length(data.aws_availability_zones.available.names)}"

  subnet_id      = "${element(aws_subnet.privatesubnet.*.id,count.index)}"
  route_table_id = "${element(aws_route_table.private_subnet_route_table.*.id, count.index)}"
}

resource "aws_security_group" "security_group_public" {
  name   = "${var.name}-public-securitygroup"
  vpc_id = "${aws_vpc.vpc.id}"
  description = "Enable ssh traffic from own PC, http traffic from world and all outgoing traffic"

  ingress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.ip_address_test_pc}/32"]
    protocol    = "-1"
    description = "Allow all traffic from the test PC"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all http traffic"
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
  vpc_id = "${aws_vpc.vpc.id}"
  description = "Enable all traffic from internal network"

  ingress {
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["10.0.0.0/16"]
    protocol    = "-1"
    description = "Allow all traffic from within this network"
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
  name = "loadbalancerprivate"

  subnets         = ["${aws_subnet.privatesubnet.*.id}"]
  security_groups = ["${aws_security_group.security_group_private.id}"]
  internal        = "true"

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags {
    Name        = "${var.name}-lb-private"
  }
}

resource "aws_autoscaling_group" "autoscaling_group_private" {
  name = "${var.name}-asg-private"
  load_balancers = ["${aws_elb.loadbalancer_private.id}"]
  launch_configuration = "${aws_launch_configuration.launch_configuration_private.id}"
  desired_capacity = 3
  min_size = 2
  max_size = 6
  health_check_grace_period = 20
  tags {
    key                 = "Name"
    value               = "${var.name}-asg-private"
    propagate_at_launch = "true"
  }
  vpc_zone_identifier = ["${aws_subnet.privatesubnet.*.id}"]
  
  depends_on = ["aws_security_group.security_group_public", "aws_route_table.public_subnet_route_table", "aws_security_group.security_group_private", "aws_route_table_association.subnet_private_route_table_association", "aws_internet_gateway.igw"]
}

resource "aws_launch_configuration" "launch_configuration_public" {
  name_prefix = "${var.name}-lc-public-"
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
  name = "loadbalancerpublic"

  subnets         = ["${aws_subnet.publicsubnet.*.id}"]
  security_groups = ["${aws_security_group.security_group_public.id}"]
  internal        = "false"

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags {
    Name        = "${var.name}-lb-public"
  }
}

resource "aws_autoscaling_group" "autoscaling_group_public" {
  name = "autoscalingGroupPublic"
  load_balancers = ["${aws_elb.loadbalancer_public.id}"]
  launch_configuration = "${aws_launch_configuration.launch_configuration_public.id}"
  desired_capacity = 3
  min_size = 2
  max_size = 6
  health_check_grace_period = 20
  tags {
    key                 = "Name"
    value               = "${var.name}-asg-public"
    propagate_at_launch = "true"
  }
  vpc_zone_identifier = ["${aws_subnet.publicsubnet.*.id}"]

  depends_on = ["aws_autoscaling_group.autoscaling_group_private", "aws_security_group.security_group_private", "aws_route_table.private_subnet_route_table"]
}

##################################################################################
# OUTPUT
##################################################################################

output "aws_elb_public_dns" {
  value = "${aws_elb.loadbalancer_public.dns_name}"
}

