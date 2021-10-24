# iac
1. Create VPC
2. Create Internet Gateway
3. Attach Internet Gateway to the VPC
4. Create Public Subnets
5. Create Public Route Table
6. Add Public Route to the Public Route Table
7. Associate the Public Subnets with the Public Route Table
8. Create Private Subnets
9. Create the Security Groups for:
    i. Application Load Balancer
    ii. ssh
    iii. EC2
    iv. RDS

# Create a NAT Gateway
1. Allocate Elastic IP Address
2. Create NAT Gateway in each Public Subnets
3. Create a Private Route Table 1
4. Add a route to point internet-bound traffic to the NAT Gateway
5. Associate Private Subnets with Private Route Table
6. Repeat step 3, 4, 5 Private Route Table 2