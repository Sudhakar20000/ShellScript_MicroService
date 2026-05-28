#!/bin/bash

set -e

# =========================
# FIX PATH ISSUE (IMPORTANT)
# =========================
export PATH=$PATH:/usr/local/bin

# =========================
# AWS CLI PATH
# =========================
AWS_CMD="/usr/local/bin/aws"

if [[ ! -f "$AWS_CMD" ]]; then
    AWS_CMD=$(which aws)
fi

if [[ -z "$AWS_CMD" ]]; then
    echo "❌ AWS CLI not found"
    exit 1
fi

# =========================
# CONFIG
# =========================
AMI_ID="ami-0220d79f3f480ecf5"
INSTANCE_TYPE="t3.micro"

HOSTED_ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN="sudhakar.shop"

VPC_ID="vpc-071995b72d576a774"
SUBNET_ID="subnet-08abe1757462b2432"

# =========================
# ARGUMENTS
# =========================
ACTION=$1
shift || true

if [[ -z "$ACTION" ]]; then
    echo "Usage: $0 create|delete component..."
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Provide at least one component"
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

echo "Your IP: $MY_IP"

# =========================
# CREATE FUNCTION
# =========================
create() {
    component=$1

    echo "=============================="
    echo "Creating: $component"
    echo "=============================="

    # -------------------------
    # SG CHECK
    # -------------------------
    SG_ID=$($AWS_CMD ec2 describe-security-groups \
        --filters Name=group-name,Values=robo-${component} \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)

    if [[ "$SG_ID" == "None" || "$SG_ID" == "null" || -z "$SG_ID" ]]; then

        echo "Creating Security Group..."

        SG_ID=$($AWS_CMD ec2 create-security-group \
            --group-name robo-${component} \
            --description "SG for ${component}" \
            --vpc-id "$VPC_ID" \
            --query 'GroupId' \
            --output text)

        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr "${MY_IP}/32" || true

        echo "SG created: $SG_ID"

    else
        echo "SG already exists: $SG_ID"
    fi

    # -------------------------
    # INSTANCE CHECK
    # -------------------------
    INSTANCE_ID=$($AWS_CMD ec2 describe-instances \
        --filters "Name=tag:Name,Values=ec2-${component}" \
                  "Name=instance-state-name,Values=pending,running,stopped,stopping" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)

    if [[ "$INSTANCE_ID" != "None" && "$INSTANCE_ID" != "null" && -n "$INSTANCE_ID" ]]; then
        echo "Instance already exists: $INSTANCE_ID"
        return
    fi

    # -------------------------
    # CREATE EC2
    # -------------------------
    echo "Launching EC2..."

    INSTANCE_ID=$($AWS_CMD ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --security-group-ids "$SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ec2-${component}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo "Instance: $INSTANCE_ID"

    $AWS_CMD ec2 wait instance-running --instance-ids "$INSTANCE_ID"

    PRIVATE_IP=$($AWS_CMD ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)

    PUBLIC_IP=$($AWS_CMD ec2 describe-instances \
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
        RECORD_NAME="$component.$DOMAIN"
        IP="$PRIVATE_IP"
    fi

    cat > /tmp/route53.json <<EOF
{
  "Comment": "UPSERT $component",
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

    $AWS_CMD route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch file:///tmp/route53.json >/dev/null

    rm -f /tmp/route53.json

    echo "Route53 updated: $RECORD_NAME -> $IP"
}

# =========================
# DELETE FUNCTION
# =========================
delete() {
    component=$1

    echo "=============================="
    echo "Deleting: $component"
    echo "=============================="

    INSTANCE_ID=$($AWS_CMD ec2 describe-instances \
        --filters "Name=tag:Name,Values=ec2-${component}" \
                  "Name=instance-state-name,Values=pending,running,stopped,stopping" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)

    if [[ "$INSTANCE_ID" == "None" || "$INSTANCE_ID" == "null" || -z "$INSTANCE_ID" ]]; then
        echo "Instance not found"
    else
        echo "Terminating: $INSTANCE_ID"

        $AWS_CMD ec2 terminate-instances --instance-ids "$INSTANCE_ID"
        $AWS_CMD ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"

        echo "Instance deleted"
    fi

    SG_ID=$($AWS_CMD ec2 describe-security-groups \
        --filters Name=group-name,Values=robo-${component} \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)

    if [[ "$SG_ID" != "None" && "$SG_ID" != "null" && -n "$SG_ID" ]]; then
        $AWS_CMD ec2 delete-security-group --group-id "$SG_ID" || true
        echo "SG deleted: $SG_ID"
    else
        echo "SG not found"
    fi
}

# =========================
# MAIN LOOP
# =========================
for component in "$@"; do
    if [[ "$ACTION" == "create" ]]; then
        create "$component"
    elif [[ "$ACTION" == "delete" ]]; then
        delete "$component"
    else
        echo "Invalid action"
        exit 1
    fi
done