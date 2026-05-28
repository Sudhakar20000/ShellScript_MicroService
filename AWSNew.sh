#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN_NAME="sudhakar.shop"

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

# =========================
# VALIDATION
# =========================
if [ $# -lt 2 ]; then
    echo -e "$R ERROR:: At least 2 arguments required $N"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi

ACTION=$1
shift

if [[ "$ACTION" != "create" && "$ACTION" != "delete" ]]; then
    echo -e "$R ERROR:: Action must be create or delete $N"
    exit 1
fi

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
# CREATE SG
# =========================
create_sg() {
    SG_NAME=$1

    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null)

    if [[ "$SG_ID" == "None" || -z "$SG_ID" || "$SG_ID" == "null" ]]; then
        echo "Creating SG: $SG_NAME"

        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "SG for $SG_NAME" \
            --query "GroupId" \
            --output text)

        echo "Created SG: $SG_NAME ($SG_ID)"
    else
        echo "SG exists: $SG_NAME ($SG_ID)"
    fi

    echo "$SG_ID"
}

# =========================
# DELETE SG SAFELY
# =========================
delete_sg() {
    SG_NAME=$1

    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null)

    if [[ "$SG_ID" == "None" || -z "$SG_ID" || "$SG_ID" == "null" ]]; then
        echo "SG already deleted: $SG_NAME"
        return
    fi

    # check if still attached
    IN_USE=$(aws ec2 describe-instances \
        --filters "Name=instance.group-id,Values=$SG_ID" \
        --query "Reservations[]" \
        --output text)

    if [[ -z "$IN_USE" ]]; then
        echo "Deleting SG: $SG_NAME ($SG_ID)"
        aws ec2 delete-security-group --group-id $SG_ID
    else
        echo "SG in use, skipping delete: $SG_NAME"
    fi
}

# =========================
# MAIN LOOP
# =========================
for instance in "$@"; do

    INSTANCE_ID=$(get_instance_id $instance)
    SG_NAME="roboshop-$instance"

    if [[ "$ACTION" == "create" ]]; then

        SG_ID=$(create_sg "$SG_NAME")

        echo "Launching: roboshop-$instance"

        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id $AMI_ID \
            --instance-type t3.micro \
            --security-group-ids "$SG_ID" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
            --query 'Instances[0].InstanceId' \
            --output text)

        aws ec2 wait instance-running --instance-ids $INSTANCE_ID
        echo "Instance running: $INSTANCE_ID"

        # Route53
        if [[ "$instance" == "frontend" ]]; then
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
            R53="$DOMAIN_NAME"
        else
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
            R53="$instance.$DOMAIN_NAME"
        fi

        aws route53 change-resource-record-sets \
        --hosted-zone-id $ZONE_ID \
        --change-batch "{
            \"Comment\": \"UPSERT\",
            \"Changes\": [{
                \"Action\": \"UPSERT\",
                \"ResourceRecordSet\": {
                    \"Name\": \"$R53\",
                    \"Type\": \"A\",
                    \"TTL\": 1,
                    \"ResourceRecords\": [{\"Value\": \"$IP\"}]
                }
            }]
        }"

        echo "Route53 updated: $R53"

    else
        # ================= DELETE =================

        if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
            echo "$instance already deleted"
            continue
        fi

        # GET IP BEFORE TERMINATION
        if [[ "$instance" == "frontend" ]]; then
            R53="$DOMAIN_NAME"
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        else
            R53="$instance.$DOMAIN_NAME"
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
        fi

        echo "Terminating: $instance"
        aws ec2 terminate-instances --instance-ids $INSTANCE_ID
        aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID

        # DELETE ROUTE53
        if [[ -n "$IP" && "$IP" != "None" ]]; then
            aws route53 change-resource-record-sets \
            --hosted-zone-id $ZONE_ID \
            --change-batch "{
                \"Comment\": \"DELETE\",
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

        # DELETE SG
        delete_sg "$SG_NAME"

        echo "Cleanup complete: $instance"
    fi
done