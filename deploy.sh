#!/bin/bash
set -e

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
PROJECT_TAG="04-capstone-practice"

VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"

API_SG_NAME="04-capstone-practice-api-sg"
DB_SG_NAME="04-capstone-practice-db-sg"

# --------------------------------------------------
# Helpers
# --------------------------------------------------
tag_resource() {
    aws ec2 create-tags \
        --resources "$1" \
        --tags "Key=Project,Value=${PROJECT_TAG}"
}

command -v aws >/dev/null 2>&1 || {
    echo "AWS CLI is not installed."
    exit 1
}

echo "Checking AWS credentials..."
aws sts get-caller-identity >/dev/null

# --------------------------------------------------
# VPC
# --------------------------------------------------
echo "Creating or reusing VPC..."
VPC_ID="$(
    aws ec2 describe-vpcs \
        --filters \
            "Name=tag:Project,Values=${PROJECT_TAG}" \
            "Name=cidr-block,Values=${VPC_CIDR}" \
        --query "Vpcs[0].VpcId" \
        --output text
)"

if [[ "$VPC_ID" == "None" ]]; then
    VPC_ID="$(
        aws ec2 create-vpc \
            --cidr-block "$VPC_CIDR" \
            --query "Vpc.VpcId" \
            --output text
    )"

    aws ec2 wait vpc-available \
        --vpc-ids "$VPC_ID"
fi

tag_resource "$VPC_ID"

# --------------------------------------------------
# Public subnet
# --------------------------------------------------
echo "Creating or reusing public subnet..."

PUBLIC_SUBNET_ID="$(
    aws ec2 describe-subnets \
        --filters \
            "Name=vpc-id,Values=${VPC_ID}" \
            "Name=cidr-block,Values=${PUBLIC_SUBNET_CIDR}" \
        --query "Subnets[0].SubnetId" \
        --output text
)"

if [[ "$PUBLIC_SUBNET_ID" == "None" ]]; then
    PUBLIC_SUBNET_ID="$(
        aws ec2 create-subnet \
            --vpc-id "$VPC_ID" \
            --cidr-block "$PUBLIC_SUBNET_CIDR" \
            --query "Subnet.SubnetId" \
            --output text
    )"

    aws ec2 wait subnet-available \
        --subnet-ids "$PUBLIC_SUBNET_ID"
fi

tag_resource "$PUBLIC_SUBNET_ID"

# assign public IP to EC2s created in this subnet
aws ec2 modify-subnet-attribute \
    --subnet-id "$PUBLIC_SUBNET_ID" \
    --map-public-ip-on-launch

# --------------------------------------------------
# Private subnet
# --------------------------------------------------
echo "Creating or reusing private subnet..."

PRIVATE_SUBNET_ID="$(
    aws ec2 describe-subnets \
        --filters \
            "Name=vpc-id,Values=${VPC_ID}" \
            "Name=cidr-block,Values=${PRIVATE_SUBNET_CIDR}" \
        --query "Subnets[0].SubnetId" \
        --output text
)"

if [[ "$PRIVATE_SUBNET_ID" == "None" ]]; then
    PRIVATE_SUBNET_ID="$(
        aws ec2 create-subnet \
            --vpc-id "$VPC_ID" \
            --cidr-block "$PRIVATE_SUBNET_CIDR" \
            --query "Subnet.SubnetId" \
            --output text
    )"

    aws ec2 wait subnet-available \
        --subnet-ids "$PRIVATE_SUBNET_ID"
fi

tag_resource "$PRIVATE_SUBNET_ID"

# --------------------------------------------------
# Internet Gateway
# --------------------------------------------------
echo "Creating or reusing Internet Gateway..."

IGW_ID="$(
    aws ec2 describe-internet-gateways \
        --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
        --query "InternetGateways[0].InternetGatewayId" \
        --output text
)"

if [[ "$IGW_ID" == "None" ]]; then
    IGW_ID="$(
        aws ec2 create-internet-gateway \
            --query "InternetGateway.InternetGatewayId" \
            --output text
    )"
fi

tag_resource "$IGW_ID"

aws ec2 attach-internet-gateway \
    --internet-gateway-id "$IGW_ID" \
    --vpc-id "$VPC_ID" \
    >/dev/null 2>&1 || true

# --------------------------------------------------
# Public route table
# --------------------------------------------------
echo "Creating or reusing public route table..."

PUBLIC_RTB_ID="$(
    aws ec2 describe-route-tables \
        --filters \
            "Name=association.subnet-id,Values=${PUBLIC_SUBNET_ID}" \
        --query "RouteTables[0].RouteTableId" \
        --output text
)"

if [[ "$PUBLIC_RTB_ID" == "None" ]]; then
    PUBLIC_RTB_ID="$(
        aws ec2 create-route-table \
            --vpc-id "$VPC_ID" \
            --query "RouteTable.RouteTableId" \
            --output text
    )"

    aws ec2 associate-route-table \
        --route-table-id "$PUBLIC_RTB_ID" \
        --subnet-id "$PUBLIC_SUBNET_ID" \
        >/dev/null
fi

tag_resource "$PUBLIC_RTB_ID"

# Public subnet -> Internet Gateway
aws ec2 create-route \
    --route-table-id "$PUBLIC_RTB_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "$IGW_ID" \
    >/dev/null 2>&1 || \
aws ec2 replace-route \
    --route-table-id "$PUBLIC_RTB_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "$IGW_ID" \
    >/dev/null

# --------------------------------------------------
# Elastic IP for NAT Gateway
# --------------------------------------------------
echo "Creating or reusing Elastic IP..."

NAT_EIP_ID="$(
    aws ec2 describe-addresses \
        --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
        --query "Addresses[0].AllocationId" \
        --output text
)"

if [[ "$NAT_EIP_ID" == "None" ]]; then
    NAT_EIP_ID="$(
        aws ec2 allocate-address \
            --domain vpc \
            --query "AllocationId" \
            --output text
    )"
fi

tag_resource "$NAT_EIP_ID"

# --------------------------------------------------
# NAT Gateway
# --------------------------------------------------
echo "Creating or reusing NAT Gateway..."

NAT_GATEWAY_ID="$(
    aws ec2 describe-nat-gateways \
        --filter \
            "Name=subnet-id,Values=${PUBLIC_SUBNET_ID}" \
            "Name=state,Values=pending,available" \
            "Name=tag:Project,Values=${PROJECT_TAG}" \
        --query "NatGateways[0].NatGatewayId" \
        --output text
)"

if [[ "$NAT_GATEWAY_ID" == "None" ]]; then
    NAT_GATEWAY_ID="$(
        aws ec2 create-nat-gateway \
            --subnet-id "$PUBLIC_SUBNET_ID" \
            --allocation-id "$NAT_EIP_ID" \
            --query "NatGateway.NatGatewayId" \
            --output text
    )"
fi

tag_resource "$NAT_GATEWAY_ID"

echo "Waiting for NAT Gateway..."
aws ec2 wait nat-gateway-available \
    --nat-gateway-ids "$NAT_GATEWAY_ID"

# --------------------------------------------------
# Private route table
# --------------------------------------------------
echo "Creating or reusing private route table..."

PRIVATE_RTB_ID="$(
    aws ec2 describe-route-tables \
        --filters \
            "Name=association.subnet-id,Values=${PRIVATE_SUBNET_ID}" \
        --query "RouteTables[0].RouteTableId" \
        --output text
)"

if [[ "$PRIVATE_RTB_ID" == "None" ]]; then
    PRIVATE_RTB_ID="$(
        aws ec2 create-route-table \
            --vpc-id "$VPC_ID" \
            --query "RouteTable.RouteTableId" \
            --output text
    )"

    aws ec2 associate-route-table \
        --route-table-id "$PRIVATE_RTB_ID" \
        --subnet-id "$PRIVATE_SUBNET_ID" \
        >/dev/null
fi

tag_resource "$PRIVATE_RTB_ID"

# Private subnet -> NAT Gateway
aws ec2 create-route \
    --route-table-id "$PRIVATE_RTB_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --nat-gateway-id "$NAT_GATEWAY_ID" \
    >/dev/null 2>&1 || \
aws ec2 replace-route \
    --route-table-id "$PRIVATE_RTB_ID" \
    --destination-cidr-block "0.0.0.0/0" \
    --nat-gateway-id "$NAT_GATEWAY_ID" \
    >/dev/null

# --------------------------------------------------
# API Security Group
# --------------------------------------------------
echo "Creating or reusing API Security Group..."

API_SG_ID="$(
    aws ec2 describe-security-groups \
        --filters \
            "Name=vpc-id,Values=${VPC_ID}" \
            "Name=group-name,Values=${API_SG_NAME}" \
        --query "SecurityGroups[0].GroupId" \
        --output text
)"

if [[ "$API_SG_ID" == "None" ]]; then
    API_SG_ID="$(
        aws ec2 create-security-group \
            --group-name "$API_SG_NAME" \
            --description "Journal API security group" \
            --vpc-id "$VPC_ID" \
            --query "GroupId" \
            --output text
    )"
fi

tag_resource "$API_SG_ID"

# SSH
aws ec2 authorize-security-group-ingress \
    --group-id "$API_SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "0.0.0.0/0" \
    >/dev/null 2>&1 || true

# HTTP
aws ec2 authorize-security-group-ingress \
    --group-id "$API_SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr "0.0.0.0/0" \
    >/dev/null 2>&1 || true

# HTTPS
aws ec2 authorize-security-group-ingress \
    --group-id "$API_SG_ID" \
    --protocol tcp \
    --port 443 \
    --cidr "0.0.0.0/0" \
    >/dev/null 2>&1 || true

# Outbound internet
aws ec2 authorize-security-group-egress \
    --group-id "$API_SG_ID" \
    --protocol -1 \
    --cidr "0.0.0.0/0" \
    >/dev/null 2>&1 || true

# --------------------------------------------------
# Database Security Group
# --------------------------------------------------
echo "Creating or reusing database Security Group..."

DB_SG_ID="$(
    aws ec2 describe-security-groups \
        --filters \
            "Name=vpc-id,Values=${VPC_ID}" \
            "Name=group-name,Values=${DB_SG_NAME}" \
        --query "SecurityGroups[0].GroupId" \
        --output text
)"

if [[ "$DB_SG_ID" == "None" ]]; then
    DB_SG_ID="$(
        aws ec2 create-security-group \
            --group-name "$DB_SG_NAME" \
            --description "Journal database security group" \
            --vpc-id "$VPC_ID" \
            --query "GroupId" \
            --output text
    )"
fi

tag_resource "$DB_SG_ID"


# SSH only from public subnet
aws ec2 authorize-security-group-ingress \
    --group-id "$DB_SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "$PUBLIC_SUBNET_CIDR" \
    >/dev/null 2>&1 || true

# PostgreSQL only from public subnet
aws ec2 authorize-security-group-ingress \
    --group-id "$DB_SG_ID" \
    --protocol tcp \
    --port 5432 \
    --cidr "$PUBLIC_SUBNET_CIDR" \
    >/dev/null 2>&1 || true

# Outbound internet through NAT Gateway
aws ec2 authorize-security-group-egress \
    --group-id "$DB_SG_ID" \
    --protocol -1 \
    --cidr "0.0.0.0/0" \
    >/dev/null 2>&1 || true
    
# --------------------------------------------------
# Verification
# --------------------------------------------------

echo
echo "=================================================="
echo "Verifying network configuration"
echo "=================================================="

echo
echo "Public subnet default route:"
echo "Expected: 0.0.0.0/0 -> Internet Gateway"

aws ec2 describe-route-tables \
    --route-table-ids "$PUBLIC_RTB_ID" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].[DestinationCidrBlock,GatewayId,State]' \
    --output table \
    --no-cli-pager

echo
echo "Private subnet default route:"
echo "Expected: 0.0.0.0/0 -> NAT Gateway"

aws ec2 describe-route-tables \
    --route-table-ids "$PRIVATE_RTB_ID" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].[DestinationCidrBlock,NatGatewayId,State]' \
    --output table \
    --no-cli-pager

echo
echo "=================================================="
echo "API Security Group"
echo "=================================================="

echo
echo "Inbound rules:"
echo "Expected:"
echo "  TCP 22  from 0.0.0.0/0"
echo "  TCP 80  from 0.0.0.0/0"
echo "  TCP 443 from 0.0.0.0/0"

aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=${API_SG_ID}" \
    --query 'SecurityGroupRules[?IsEgress==`false`].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,Source:CidrIpv4}' \
    --output table \
    --no-cli-pager

echo
echo "Outbound rules:"
echo "Expected: all traffic to 0.0.0.0/0"

aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=${API_SG_ID}" \
    --query 'SecurityGroupRules[?IsEgress==`true`].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,Destination:CidrIpv4}' \
    --output table \
    --no-cli-pager

echo
echo "=================================================="
echo "Database Security Group"
echo "=================================================="

echo
echo "Inbound rules:"
echo "Expected:"
echo "  TCP 22   from ${PUBLIC_SUBNET_CIDR}"
echo "  TCP 5432 from ${PUBLIC_SUBNET_CIDR}"

aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=${DB_SG_ID}" \
    --query 'SecurityGroupRules[?IsEgress==`false`].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,Source:CidrIpv4}' \
    --output table \
    --no-cli-pager

echo
echo "Outbound rules:"
echo "Expected: all traffic to 0.0.0.0/0"

aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=${DB_SG_ID}" \
    --query 'SecurityGroupRules[?IsEgress==`true`].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort,Destination:CidrIpv4}' \
    --output table \
    --no-cli-pager

echo
echo "=================================================="
echo "Network provisioning completed"
echo "=================================================="
echo "VPC:                 $VPC_ID"
echo "Public subnet:       $PUBLIC_SUBNET_ID"
echo "Private subnet:      $PRIVATE_SUBNET_ID"
echo "Internet Gateway:    $IGW_ID"
echo "Public route table:  $PUBLIC_RTB_ID"
echo "Private route table: $PRIVATE_RTB_ID"
echo "NAT Gateway:         $NAT_GATEWAY_ID"
echo "API Security Group:  $API_SG_ID"
echo "DB Security Group:   $DB_SG_ID"
echo "Tag:                 Project=$PROJECT_TAG"