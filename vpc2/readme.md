# Which components are deployed?

https://technology.amis.nl/aws/differences-between-cloudformation-terraform-and-ansible-in-deployment-of-objects-in-aws/

The solution that is deployed is not that complicated: there is a VPC with an internet gateway, three public subnets and three private subnets. There is one public and one private subnet per availability zone. The private networks are connected to the public networks with one NAT gateway per public network, to ensure high availability for each of the AZ’s. Routing tables and security groups are created to allow traffic to go from and to the EC2’s.

The EC2’s are t2.micro Amazon Unix-machines. Each of them gets a webserver (httpd) with a very simple message in the index.html. They are deployed by an auto scaling group with three desired nodes. There are two load balancers: one for the nodes in the private networks and one for the nodes in the public networks. The CloudFormation, Terraform and Ansible scripts will output the DNS-name of the public load balancer when they are ready.

To make the solution a little bit easier, the EC2’s in the private network are deployed first. The VM’s in the public network will first give back their own message (“Foreground website”) and then do a curl to the internal load balancer to get the text of the EC2’s in the private network (“Background info”) after that. Because the index.html is a static file which is created at the deployment of the EC2’s, the scripts must deploy the EC2’s in the private network first.

When you want to deploy these scripts yourself, you first need to create a key within EC2  to be able to ssh to the EC2’s. The security group that is used in public subnets allow all connections from a test PC (the IP-address of this PC is passed as a parameter), and web traffic from all IP-addresses.

