#!/bin/bash
set -e

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
: "${DB_PASSWORD:?Run the script with DB_PASSWORD set}"
: "${DUCKDNS_SUBDOMAIN:?Run the script with DUCKDNS_SUBDOMAIN set}"
: "${DUCKDNS_TOKEN:?Run the script with DUCKDNS_TOKEN set}"
: "${OPENAI_API_KEY:?Run the script with OPENAI_API_KEY set}"

PROJECT_TAG="04-capstone-practice"

VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
PRIVATE_SUBNET_CIDR="10.0.2.0/24"

API_SG_NAME="04-capstone-practice-api-sg"
DB_SG_NAME="04-capstone-practice-db-sg"

API_INSTANCE_NAME="04-capstone-practice-api"
API_INSTANCE_TYPE="t3.small" # 2 GiB RAM, so no swap is required
API_PORT="8000"
API_REPOSITORY_URL="https://github.com/lukasz789/journal-starter.git"
OPENAI_BASE_URL="https://bedrock-runtime.us-east-1.amazonaws.com/openai/v1"
OPENAI_MODEL="openai.gpt-oss-20b-1:0"

DB_INSTANCE_NAME="04-capstone-practice-db"
DB_INSTANCE_TYPE="t3.small" # 2 GiB RAM, so no swap is required
DB_NAME="career_journal"
DB_USER="career_journal_app"
DB_PORT="5432"

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
    --port "$DB_PORT" \
    --cidr "$PUBLIC_SUBNET_CIDR" \
    >/dev/null 2>&1 || true

# Outbound internet through NAT Gateway
aws ec2 authorize-security-group-egress \
    --group-id "$DB_SG_ID" \
    --protocol -1 \
    --cidr "0.0.0.0/0" \
    >/dev/null 2>&1 || true

# --------------------------------------------------
# Amazon Linux 2023 AMI
# --------------------------------------------------
echo "Finding the latest Amazon Linux 2023 AMI..."

DB_AMI_ID="$(
    aws ec2 describe-images \
        --owners amazon \
        --filters \
            "Name=name,Values=al2023-ami-2023.*-kernel-6.1-x86_64" \
            "Name=architecture,Values=x86_64" \
            "Name=root-device-type,Values=ebs" \
            "Name=state,Values=available" \
        --query "sort_by(Images, &CreationDate)[-1].ImageId" \
        --output text
)"

if [[ "$DB_AMI_ID" == "None" || -z "$DB_AMI_ID" ]]; then
    echo "Amazon Linux 2023 AMI was not found in the current AWS region."
    exit 1
fi

# --------------------------------------------------
# Database VM user data
# --------------------------------------------------
echo "Preparing database VM user data..."

DB_USER_DATA="$(
    printf '#!/bin/bash\n'
    printf 'export DB_NAME=%s\n' "$DB_NAME"
    printf 'export DB_USER=%s\n' "$DB_USER"
    printf 'export DB_PASSWORD=%s\n' "$DB_PASSWORD"
    printf 'export API_SUBNET_CIDR=%s\n' "$PUBLIC_SUBNET_CIDR"
    printf "cat > /tmp/database_setup.sql <<'DATABASE_SQL'\n"
    cat database_setup.sql
    printf '\nDATABASE_SQL\n'
    tail -n +2 scripts/database_user_data.sh
)"

# --------------------------------------------------
# Database VM
# --------------------------------------------------
echo "Creating or reusing database VM..."

DB_INSTANCE_ID="$(
    aws ec2 describe-instances \
        --filters \
            "Name=tag:Project,Values=${PROJECT_TAG}" \
            "Name=tag:Name,Values=${DB_INSTANCE_NAME}" \
            "Name=instance-state-name,Values=pending,running" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text
)"

if [[ "$DB_INSTANCE_ID" == "None" ]]; then
    DB_INSTANCE_ID="$(
        aws ec2 run-instances \
            --image-id "$DB_AMI_ID" \
            --instance-type "$DB_INSTANCE_TYPE" \
            --subnet-id "$PRIVATE_SUBNET_ID" \
            --security-group-ids "$DB_SG_ID" \
            --user-data "$DB_USER_DATA" \
            --query "Instances[0].InstanceId" \
            --output text
    )"
fi

tag_resource "$DB_INSTANCE_ID"

aws ec2 create-tags \
    --resources "$DB_INSTANCE_ID" \
    --tags "Key=Name,Value=${DB_INSTANCE_NAME}"

aws ec2 wait instance-running --instance-ids "$DB_INSTANCE_ID"

DB_PRIVATE_IP="$(
    aws ec2 describe-instances \
        --instance-ids "$DB_INSTANCE_ID" \
        --query "Reservations[0].Instances[0].PrivateIpAddress" \
        --output text
)"

DB_VOLUME_ID="$(
    aws ec2 describe-instances \
        --instance-ids "$DB_INSTANCE_ID" \
        --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" \
        --output text
)"

DB_NETWORK_INTERFACE_ID="$(
    aws ec2 describe-instances \
        --instance-ids "$DB_INSTANCE_ID" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId" \
        --output text
)"

tag_resource "$DB_VOLUME_ID"
tag_resource "$DB_NETWORK_INTERFACE_ID"

# --------------------------------------------------
# Database connection
# --------------------------------------------------
DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_PRIVATE_IP}:${DB_PORT}/${DB_NAME}"

printf 'DATABASE_URL=%s\n' "$DATABASE_URL" > database_connection.env
chmod 600 database_connection.env

# --------------------------------------------------
# Ubuntu 24.04 AMI
# --------------------------------------------------
echo "Finding the latest Ubuntu 24.04 AMI..."

API_AMI_ID="$(
    aws ec2 describe-images \
        --owners 099720109477 \
        --filters \
            "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
            "Name=architecture,Values=x86_64" \
            "Name=root-device-type,Values=ebs" \
            "Name=state,Values=available" \
        --query "sort_by(Images, &CreationDate)[-1].ImageId" \
        --output text
)"

if [[ "$API_AMI_ID" == "None" || -z "$API_AMI_ID" ]]; then
    echo "Ubuntu 24.04 AMI was not found in the current AWS region."
    exit 1
fi

# --------------------------------------------------
# API VM user data
# --------------------------------------------------
echo "Preparing API VM user data..."

API_USER_DATA="$(
    printf '#!/bin/bash\n'
    printf 'export DATABASE_URL=%s\n' "$DATABASE_URL"
    printf 'export API_REPOSITORY_URL=%s\n' "$API_REPOSITORY_URL"
    printf 'export API_PORT=%s\n' "$API_PORT"
    printf 'export API_DOMAIN=%s\n' "${DUCKDNS_SUBDOMAIN}.duckdns.org"
    printf 'export OPENAI_API_KEY=%s\n' "$OPENAI_API_KEY"
    printf 'export OPENAI_BASE_URL=%s\n' "$OPENAI_BASE_URL"
    printf 'export OPENAI_MODEL=%s\n' "$OPENAI_MODEL"
    tail -n +2 scripts/api_user_data.sh
)"

# --------------------------------------------------
# API VM
# --------------------------------------------------
echo "Creating or reusing API VM..."

API_INSTANCE_ID="$(
    aws ec2 describe-instances \
        --filters \
            "Name=tag:Project,Values=${PROJECT_TAG}" \
            "Name=tag:Name,Values=${API_INSTANCE_NAME}" \
            "Name=instance-state-name,Values=pending,running" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text
)"

if [[ "$API_INSTANCE_ID" == "None" ]]; then
    API_INSTANCE_ID="$(
        aws ec2 run-instances \
            --image-id "$API_AMI_ID" \
            --instance-type "$API_INSTANCE_TYPE" \
            --subnet-id "$PUBLIC_SUBNET_ID" \
            --security-group-ids "$API_SG_ID" \
            --associate-public-ip-address \
            --user-data "$API_USER_DATA" \
            --query "Instances[0].InstanceId" \
            --output text
    )"
fi

tag_resource "$API_INSTANCE_ID"

aws ec2 create-tags \
    --resources "$API_INSTANCE_ID" \
    --tags "Key=Name,Value=${API_INSTANCE_NAME}"

aws ec2 wait instance-running --instance-ids "$API_INSTANCE_ID"

API_PUBLIC_IP="$(
    aws ec2 describe-instances \
        --instance-ids "$API_INSTANCE_ID" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text
)"

# Point the DuckDNS domain to the API VM.
DUCKDNS_RESPONSE="$(
    curl --silent \
        "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=${API_PUBLIC_IP}"
)"

if [[ "$DUCKDNS_RESPONSE" != "OK" ]]; then
    echo "DuckDNS update failed: $DUCKDNS_RESPONSE"
    exit 1
fi

echo "DuckDNS domain updated: ${DUCKDNS_SUBDOMAIN}.duckdns.org -> ${API_PUBLIC_IP}"

API_PRIVATE_IP="$(
    aws ec2 describe-instances \
        --instance-ids "$API_INSTANCE_ID" \
        --query "Reservations[0].Instances[0].PrivateIpAddress" \
        --output text
)"

API_VOLUME_ID="$(
    aws ec2 describe-instances \
        --instance-ids "$API_INSTANCE_ID" \
        --query "Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId" \
        --output text
)"

API_NETWORK_INTERFACE_ID="$(
    aws ec2 describe-instances \
        --instance-ids "$API_INSTANCE_ID" \
        --query "Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId" \
        --output text
)"

tag_resource "$API_VOLUME_ID"
tag_resource "$API_NETWORK_INTERFACE_ID"

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
echo "Database VM"
echo "=================================================="

echo
echo "Expected:"
echo "  State: running"
echo "  Subnet: ${PRIVATE_SUBNET_ID}"
echo "  Public IP: None"
echo "  Security Group: ${DB_SG_ID}"

aws ec2 describe-instances \
    --instance-ids "$DB_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].{State:State.Name,Subnet:SubnetId,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,SecurityGroup:SecurityGroups[0].GroupId}' \
    --output table \
    --no-cli-pager

echo
echo "=================================================="
echo "API VM"
echo "=================================================="

echo
echo "Expected:"
echo "  State: running"
echo "  Subnet: ${PUBLIC_SUBNET_ID}"
echo "  Public IP: ${API_PUBLIC_IP}"
echo "  Security Group: ${API_SG_ID}"

aws ec2 describe-instances \
    --instance-ids "$API_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].{State:State.Name,Subnet:SubnetId,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,SecurityGroup:SecurityGroups[0].GroupId}' \
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
echo "  TCP 22 from ${PUBLIC_SUBNET_CIDR}"
echo "  TCP ${DB_PORT} from ${PUBLIC_SUBNET_CIDR}"

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
echo "Provisioning completed"
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
echo "DB AMI:              $DB_AMI_ID"
echo "DB Instance:         $DB_INSTANCE_ID"
echo "DB private IP:       $DB_PRIVATE_IP"
echo "DB connection file:  database_connection.env"
echo "API AMI:             $API_AMI_ID"
echo "API Instance:        $API_INSTANCE_ID"
echo "API private IP:      $API_PRIVATE_IP"
echo "API public IP:       $API_PUBLIC_IP"
echo "API domain:          ${DUCKDNS_SUBDOMAIN}.duckdns.org"
echo "Tag:                 Project=$PROJECT_TAG"
