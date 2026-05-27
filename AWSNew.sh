#!/bin/bash

set -euo pipefail

AMI_ID="ami-0220d79f3f480ecf5"
INSTANCE_TYPE="t3.micro"

HOSTED_ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN="sudhakar.shop"

VPC_ID="vpc-071995b72d576a774"
SUBNET_ID="subnet-08abe1757462b2432"

MY_IP=$(curl -s ifconfig.me)

ACTION="${1:-}"
shift || true

if [[ -z "$ACTION" ]]; then
    echo "Usage:"
    echo "./aws.sh create mongodb nginx"
    echo "./aws.sh delete frontend"
    exit 1
fi

if [[ $# -eq 0 ]]; then
    echo "Please provide at least one component"
    exit 1
fi


# =========================
# Helpers
# =========================
is_valid() {
    [[ "$1" =~ ^[a-zA-Z0-9-]+$ ]]
}

get_instance_id() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=ec2-$1" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text 2>/dev/null || true
}

get_sg_id() {
    aws ec2 describe-security-groups \
        --filters Name=group-name,Values=robo-$1 \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || true
}


# =========================
# CREATE
# =========================
create() {

    component="$1"

    echo "----------------------------"
    echo "Creating: $component"
    echo "----------------------------"

    if ! is_valid "$component"; then
        echo "Invalid component name: $component"
        return
    fi

    SG_ID=$(get_sg_id "$component")

    if [[ -z "$SG_ID" || "$SG_ID" == "None" || "$SG_ID" == "null" ]]; then

        echo "Creating Security Group..."

        SG_ID=$(aws ec2 create-security-group \
            --group-name robo-$component \
            --description "SG for $component" \
            --vpc-id "$VPC_ID" \
            --query 'GroupId' \
            --output text)

        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr "${MY_IP}/32"

        echo "SG created: $SG_ID"
    else
        echo "SG already exists: $SG_ID"
    fi


    INSTANCE_ID=$(get_instance_id "$component")

    if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" && "$INSTANCE_ID" != "null" ]]; then
        echo "EC2 already exists: $INSTANCE_ID"
        return
    fi


    echo "Launching EC2..."

    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --security-group-ids "$SG_ID" \
        --subnet-id "$SUBNET_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=ec2-$component}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    echo "Instance created: $INSTANCE_ID"

    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

    PRIVATE_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)

    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    # ---------------- Route53 ----------------

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
      "TTL": 1,
      "ResourceRecords": [{"Value": "$IP"}]
    }
  }]
}
EOF

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch file://"$ROUTE_FILE" >/dev/null

    rm -f "$ROUTE_FILE"

    echo "Route53 updated: $RECORD_NAME -> $IP"
}


# =========================
# DELETE
# =========================
delete() {

    component="$1"

    echo "----------------------------"
    echo "Deleting: $component"
    echo "----------------------------"

    INSTANCE_ID=$(get_instance_id "$component")

    if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" || "$INSTANCE_ID" == "null" ]]; then
        echo "No EC2 found"
    else

        PRIVATE_IP=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' \
            --output text)

        PUBLIC_IP=$(aws ec2 describe-instances \
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

        ROUTE_FILE="/tmp/route53-${component}-del.json"

        cat > "$ROUTE_FILE" <<EOF
{
  "Comment": "DELETE record for $component",
  "Changes": [{
    "Action": "DELETE",
    "ResourceRecordSet": {
      "Name": "$RECORD_NAME",
      "Type": "A",
      "TTL": 1,
      "ResourceRecords": [{"Value": "$IP"}]
    }
  }]
}
EOF

        aws route53 change-resource-record-sets \
            --hosted-zone-id "$HOSTED_ZONE_ID" \
            --change-batch file://"$ROUTE_FILE" >/dev/null 2>&1 || true

        rm -f "$ROUTE_FILE"

        echo "Terminating EC2..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"

        echo "EC2 deleted"
    fi


    SG_ID=$(get_sg_id "$component")

    if [[ -n "$SG_ID" && "$SG_ID" != "None" && "$SG_ID" != "null" ]]; then
        aws ec2 delete-security-group --group-id "$SG_ID" || true
        echo "SG deleted: $SG_ID"
    else
        echo "SG not found"
    fi
}


# =========================
# MAIN
# =========================
for component in "$@"
do
    if [[ "$ACTION" == "create" ]]; then
        create "$component"
    elif [[ "$ACTION" == "delete" ]]; then
        delete "$component"
    else
        echo "Invalid action: $ACTION"
        exit 1
    fi
done