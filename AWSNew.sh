#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN_NAME="sudhakar.shop"

# =========================
# GET INSTANCE ID
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
# GET INSTANCE STATUS (IMPORTANT)
# =========================
get_instance_state(){
    id=$1
    aws ec2 describe-instances \
        --instance-ids "$id" \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text 2>/dev/null
}

# =========================
# GET SG ID
# =========================
get_sg(){
    name=$1
    aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$name" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null
}

# =========================
# MAIN
# =========================
ACTION=$1
shift

for instance in "$@"; do

SG_NAME="roboshop-$instance"
INSTANCE_ID=$(get_instance_id "$instance")

if [[ "$ACTION" == "delete" ]]; then

    # STEP 1: CHECK INSTANCE EXISTS
    if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
        echo "$instance already deleted"
        continue
    fi

    echo "Found instance: $INSTANCE_ID"

    # STEP 2: GET IP + SG BEFORE TERMINATION
    if [[ "$instance" == "frontend" ]]; then
        R53="$DOMAIN_NAME"
        IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    else
        R53="$instance.$DOMAIN_NAME"
        IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
    fi

    SG_ID=$(get_sg "$SG_NAME")

    # STEP 3: TERMINATE INSTANCE
    echo "Terminating instance: $instance"
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID

    # STEP 4: DELETE ROUTE53
    if [[ -n "$IP" && "$IP" != "None" ]]; then
        aws route53 change-resource-record-sets \
        --hosted-zone-id $ZONE_ID \
        --change-batch "{
            \"Comment\": \"DELETE record\",
            \"Changes\": [{
                \"Action\": \"DELETE\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$R53\",
                    \"Type\": \"A\",
                    \"TTL\": 1,
                    \"ResourceRecords\": [{\"Value\": \"$IP\"}]
                }
            }]
        }" 2>/dev/null

        echo "Route53 deleted: $R53"
    fi

    # STEP 5: DELETE SG ONLY AFTER INSTANCE IS GONE
    if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then

        IN_USE=$(aws ec2 describe-instances \
            --filters "Name=instance.group-id,Values=$SG_ID" \
            --query "Reservations[]" \
            --output text)

        if [[ -z "$IN_USE" ]]; then
            echo "Deleting SG: $SG_NAME"
            aws ec2 delete-security-group --group-id $SG_ID
        else
            echo "SG still in use, skipping: $SG_NAME"
        fi
    fi

    echo "DELETE COMPLETE: $instance"
fi

done