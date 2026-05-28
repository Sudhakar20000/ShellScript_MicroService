#!/bin/bash

set -x

# =========================
# CONFIG
# =========================

AMI_ID="ami-0220d79f3f480ecf5"
INSTANCE_TYPE="t3.micro"

HOSTED_ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN="sudhakar.shop"

VPC_ID="vpc-071995b72d576a774"
SUBNET_ID="subnet-08abe1757462b2432"

AWS_REGION="us-east-1"

ACTION=${1:-}

if [[ -z "$ACTION" ]]; then
    echo "Usage:"
    echo "./AWSNew.sh create mongodb redis"
    echo "./AWSNew.sh delete mongodb"
    exit 1
fi

shift

if [[ $# -eq 0 ]]; then
    echo "Please provide at least one component"
    exit 1
fi

# =========================
# VALIDATE AWS CLI
# =========================

aws sts get-caller-identity

if [[ $? -ne 0 ]]; then
    echo "AWS CLI not configured"
    exit 1
fi

# =========================
# PUBLIC IP
# =========================

MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')

if [[ -z "$MY_IP" ]]; then
    echo "Unable to fetch public IP"
    exit 1
fi

echo "Your Public IP: $MY_IP"

# =========================
# CREATE FUNCTION
# =========================

create() {

    component=$1

    echo "=============================="
    echo "Creating: $component"
    echo "=============================="

    # -------------------------
    # SECURITY GROUP
    # -------------------------

    SG_ID=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters Name=group-name,Values=robo-${component} \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

    if [[ "$SG_ID" == "None" || "$SG_ID" == "null" ]]; then
        SG_ID=""
    fi

    if [[ -z "$SG_ID" ]]; then

        echo "Creating Security Group..."

        SG_ID=$(aws ec2 create-security-group \
            --region "$AWS_REGION" \
            --group-name robo-${component} \
            --description "SG for ${component}" \
            --vpc-id "$VPC_ID" \
            --query 'GroupId' \
            --output text)

        echo "Created SG: $SG_ID"

        aws ec2 authorize-security-group-ingress \
            --region "$AWS_REGION" \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr "${MY_IP}/32" || true

        echo "SSH rule added"

    else
        echo "Security Group already exists: $SG_ID"
    fi

    # -------------------------
    # INSTANCE CHECK
    # -------------------------

    INSTANCE_ID=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=ec2-${component}" \
                  "Name=instance-state-name,Values=pending,running,stopped,stopping" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text)

    if [[ "$INSTANCE_ID" != "None" && "$INSTANCE_ID" != "null" ]]; then
        echo "Instance already exists: $INSTANCE_ID"
        return
    fi

    # -------------------------
    # CREATE EC2
    # -------------------------

    echo "Launching EC2..."

    INSTANCE_ID=$(aws ec2 run-instances \
        --region "$AWS_REGION" \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --security-group-ids "$SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ec2-${component}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo "Created Instance: $INSTANCE_ID"

    echo "Waiting for instance..."

    aws ec2 wait instance-running \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID"

    PRIVATE_IP=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)

    PUBLIC_IP=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    echo "Private IP: $PRIVATE_IP"
    echo "Public IP : $PUBLIC_IP"

    # -------------------------
    # ROUTE53
    # -------------------------

    if [[ "$component" == "frontend" ]]; then
        RECORD_NAME="$DOMAIN"
        IP="$PUBLIC_IP"
    else
        RECORD_NAME="${component}.${DOMAIN}"
        IP="$PRIVATE_IP"
    fi

    echo "Creating Route53 record..."

    cat > /tmp/route53.json <<EOF
{
  "Comment": "UPSERT record",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$RECORD_NAME",
      "Type": "A",
      "TTL": 60,
      "ResourceRecords": [{
        "Value": "$IP"
      }]
    }
  }]
}
EOF

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch file:///tmp/route53.json

    echo "Route53 updated: $RECORD_NAME -> $IP"

    rm -f /tmp/route53.json
}

# =========================
# DELETE FUNCTION
# =========================

delete() {

    component=$1

    echo "=============================="
    echo "Deleting: $component"
    echo "=============================="

    INSTANCE_ID=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=ec2-${component}" \
                  "Name=instance-state-name,Values=pending,running,stopped,stopping" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text)

    if [[ "$INSTANCE_ID" == "None" || "$INSTANCE_ID" == "null" ]]; then
        echo "Instance not found"
    else

        echo "Terminating Instance: $INSTANCE_ID"

        aws ec2 terminate-instances \
            --region "$AWS_REGION" \
            --instance-ids "$INSTANCE_ID"

        aws ec2 wait instance-terminated \
            --region "$AWS_REGION" \
            --instance-ids "$INSTANCE_ID"

        echo "Instance deleted"
    fi

    SG_ID=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters Name=group-name,Values=robo-${component} \
        --query 'SecurityGroups[0].GroupId' \
        --output text)

    if [[ "$SG_ID" != "None" && "$SG_ID" != "null" ]]; then

        echo "Deleting Security Group..."

        aws ec2 delete-security-group \
            --region "$AWS_REGION" \
            --group-id "$SG_ID"

        echo "Security Group deleted"
    fi
}

# =========================
# MAIN LOOP
# =========================

for component in "$@"
do

    if [[ "$ACTION" == "create" ]]; then
        create "$component"

    elif [[ "$ACTION" == "delete" ]]; then
        delete "$component"

    else
        echo "Invalid action"
        exit 1
    fi

done