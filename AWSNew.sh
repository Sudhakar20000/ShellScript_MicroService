#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN_NAME="sudhakar.shop"

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

### Validation ###
if [ $# -lt 2 ]; then
    echo -e "$R ERROR:: At least 2 arguments required $N"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi

ACTION=$1
shift

if [[ "$ACTION" != "create" && "$ACTION" != "delete" ]]; then
    echo -e "$R ERROR:: First argument must be create or delete $N"
    exit 1
fi

# =========================
# Get instance ID
# =========================
get_instance_id(){
    name=$1
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=roboshop-$name" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>/dev/null
}

# =========================
# Create SG
# =========================
create_sg() {
    SG_NAME=$1

    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null)

    if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
        echo "Creating SG: $SG_NAME"
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "SG for $SG_NAME" \
            --query "GroupId" \
            --output text)
    fi

    echo "$SG_ID"
}

# =========================
# Delete SG safely
# =========================
delete_sg() {
    SG_NAME=$1

    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null)

    if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
        echo "SG $SG_NAME already deleted"
        return
    fi

    # check if SG is in use
    ATTACHED=$(aws ec2 describe-instances \
        --filters "Name=instance.group-id,Values=$SG_ID" \
        --query "Reservations[]" \
        --output text)

    if [[ -z "$ATTACHED" ]]; then
        echo "Deleting SG: $SG_NAME ($SG_ID)"
        aws ec2 delete-security-group --group-id $SG_ID
    else
        echo "SG $SG_NAME still in use, skipping delete"
    fi
}

# =========================
# MAIN LOOP
# =========================
for instance in "$@"; do

    INSTANCE_ID=$(get_instance_id $instance)

    APP_SG_NAME="roboshop-$instance"

    if [[ "$ACTION" == "create" ]]; then

        APP_SG_ID=$(create_sg "$APP_SG_NAME")

        echo "Launching instance: roboshop-$instance"

        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id $AMI_ID \
            --instance-type t3.micro \
            --security-group-ids "$APP_SG_ID" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
            --query 'Instances[0].InstanceId' \
            --output text)

        aws ec2 wait instance-running --instance-ids $INSTANCE_ID

        echo "Instance running: $INSTANCE_ID"

        # Route53
        if [[ "$instance" == "frontend" ]]; then
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
            R53_RECORD="$DOMAIN_NAME"
        else
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
            R53_RECORD="$instance.$DOMAIN_NAME"
        fi

        aws route53 change-resource-record-sets \
        --hosted-zone-id $ZONE_ID \
        --change-batch "{
            \"Comment\": \"UPSERT record\",
            \"Changes\": [{
                \"Action\": \"UPSERT\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$R53_RECORD\",
                    \"Type\": \"A\",
                    \"TTL\": 1,
                    \"ResourceRecords\": [{\"Value\": \"$IP\"}]
                }
            }]
        }"

        echo "Route53 updated for $instance"

    else
        # ================= DELETE =================

        if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
            echo "$instance already deleted"
            continue
        fi

        echo "Terminating instance: $instance"
        aws ec2 terminate-instances --instance-ids $INSTANCE_ID
        aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID

        # Route53 delete
        if [[ "$instance" == "frontend" ]]; then
            R53_RECORD="$DOMAIN_NAME"
        else
            R53_RECORD="$instance.$DOMAIN_NAME"
        fi

        aws route53 change-resource-record-sets \
        --hosted-zone-id $ZONE_ID \
        --change-batch "{
            \"Comment\": \"DELETE record\",
            \"Changes\": [{
                \"Action\": \"DELETE\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$R53_RECORD\",
                    \"Type\": \"A\",
                    \"TTL\": 1,
                    \"ResourceRecords\": [{\"Value\": \"dummy\"}]
                }
            }]
        }" 2>/dev/null

        # Delete SG
        delete_sg "$APP_SG_NAME"

        echo "Deleted: $instance (EC2 + SG + DNS)"
    fi

done