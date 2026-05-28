#!/bin/bash

set -e

# =========================
# CONFIG
# =========================
AMI_ID="ami-0220d79f3f480ecf5"
INSTANCE_TYPE="t3.micro"
HOSTED_ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN="sudhakar.shop"
VPC_ID="vpc-071995b72d576a774"
SUBNET_ID="subnet-08abe1757462b2432"

# Detect AWS CLI path
AWS_CMD=$(which aws)
if [[ -z "$AWS_CMD" ]]; then
    echo "AWS CLI not found. Install AWS CLI v2 first."
    exit 1
fi

# =========================
# ARGUMENTS
# =========================
ACTION=$1
shift || true

if [[ -z "$ACTION" ]]; then
    echo "Usage:"
    echo "$0 create mongodb nginx"
    echo "$0 delete frontend"
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Please provide at least one component"
    exit 1
fi

# Get my public IP
MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')
if [[ -z "$MY_IP" ]]; then
    echo "Unable to fetch public IP"
    exit 1
fi

# =========================
# CREATE FUNCTION
# =========================
create() {
    component=$1
    echo "=============================="
    echo "Creating: $component"
    echo "=============================="

    # Security Group
    SG_ID=$($AWS_CMD ec2 describe-security-groups \
        --filters Name=group-name,Values=robo-${component} \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)

    if [[ -z "$SG_ID" || "$SG_ID" == "None" || "$SG_ID" == "null" ]]; then
        echo "Creating Security Group..."
        SG_ID=$($AWS_CMD ec2 create-security-group \
            --group-name robo-${component} \
            --description "SG for ${component}" \
            --vpc-id "$VPC_ID" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=robo-${component}}]" \
            --query 'GroupId' \
            --output text)

        $AWS_CMD ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr "${MY_IP}/32"

        echo "SG created: $SG_ID (SSH allowed from $MY_IP)"
    else
        echo "SG already exists: $SG_ID"
    fi

    # EC2 Check
    INSTANCE_ID=$($AWS_CMD ec2 describe-instances \
        --filters "Name=tag:Name,Values=ec2-${component}" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)

    if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" && "$INSTANCE_ID" != "null" ]]; then
        echo "EC2 already exists: $INSTANCE_ID"
        return
    fi

    # Launch EC2
    echo "Launching EC2..."
    INSTANCE_ID=$($AWS_CMD ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --security-group-ids "$SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ec2-${component}}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo "Instance created: $INSTANCE_ID"
    $AWS_CMD ec2 wait instance-running --instance-ids "$INSTANCE_ID"

    PRIVATE_IP=$($AWS_CMD ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)

    PUBLIC_IP=$($AWS_CMD ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    # Route53
    if [[ "$component" == "frontend" ]]; then
        RECORD_NAME="$DOMAIN"
        IP="$PUBLIC_IP"
    else
        RECORD_NAME="$component.$DOMAIN"
        IP="$PRIVATE_IP"
    fi

    ROUTE_FILE="/tmp/route53-${component}.json"

    cat > "$ROUTE_FILE" <<EOF
{
  "Comment": "UPSERT record for $component",
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
        --change-batch file://"$ROUTE_FILE" >/dev/null

    rm -f "$ROUTE_FILE"
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
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null)

    if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" || "$INSTANCE_ID" == "null" ]]; then
        echo "EC2 not found"
    else
        PRIVATE_IP=$($AWS_CMD ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' \
            --output text)

        PUBLIC_IP=$($AWS_CMD ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text)

        if [[ "$component" == "frontend" ]]; then
            RECORD_NAME="$DOMAIN"
            IP="$PUBLIC_IP"
        else
            RECORD_NAME="$component.$DOMAIN"
            IP="$PRIVATE_IP"
        fi

        ROUTE_FILE="/tmp/route53-del-${component}.json"
        cat > "$ROUTE_FILE" <<EOF
{
  "Comment": "DELETE record for $component",
  "Changes": [{
    "Action": "DELETE",
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
            --change-batch file://"$ROUTE_FILE" >/dev/null 2>&1 || true
        rm -f "$ROUTE_FILE"

        echo "Terminating EC2..."
        $AWS_CMD ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null
        $AWS_CMD ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
        echo "EC2 deleted"
    fi

    SG_ID=$($AWS_CMD ec2 describe-security-groups \
        --filters Name=group-name,Values=robo-${component} \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)

    if [[ -n "$SG_ID" && "$SG_ID" != "None" && "$SG_ID" != "null" ]]; then
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
        echo "Invalid action: $ACTION"
        exit 1
    fi
done