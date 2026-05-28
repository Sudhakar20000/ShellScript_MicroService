#!/bin/bash

#export PATH=$PATH:/usr/local/bin

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z03774782PWBJZ4CLRX9V"  # replace with your zone ID
DOMAIN_NAME="sudhakar.shop"      # replace with your domain name

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
    echo -e "$R ERROR:: First argument must be either create or delete $N"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi

# =========================
# Function: get instance ID (any state)
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
# Function: create security group if missing, returns SG ID
# =========================
create_sg() {
    SG_NAME=$1

    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$SG_NAME" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null)

    if [[ -z "$SG_ID" || "$SG_ID" == "None" || "$SG_ID" == "null" ]]; then
        echo "Creating Security Group: $SG_NAME"
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "Security group for $SG_NAME" \
            --query "GroupId" \
            --output text)
        echo "Created SG: $SG_NAME ($SG_ID)"
        echo "Configure ports manually as needed."
    else
        echo "Security Group already exists: $SG_NAME ($SG_ID)"
    fi

    echo $SG_ID
}

# =========================
# Main loop for instances
# =========================
for instance in "$@"; do
    INSTANCE_ID=$(get_instance_id $instance)

    if [[ "$ACTION" == "create" ]]; then

        # Create SGs and get IDs
        COMMON_SG_ID=$(create_sg "roboshop-common")
        APP_SG_ID=$(create_sg "roboshop-$instance")

        if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" || "$INSTANCE_ID" == "null" ]]; then
            echo "Launching Instance: roboshop-$instance"
            INSTANCE_ID=$(aws ec2 run-instances \
                --image-id $AMI_ID \
                --instance-type t3.micro \
                --security-group-ids $COMMON_SG_ID $APP_SG_ID \
                --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
                --query 'Instances[0].InstanceId' \
                --output text)
            echo "Launched Instance: $INSTANCE_ID"
            aws ec2 wait instance-running --instance-ids $INSTANCE_ID
            echo "Instance is running: $INSTANCE_ID"

        else
            # Check state
            STATE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[0].Instances[0].State.Name' --output text)
            if [[ "$STATE" == "stopped" ]]; then
                echo "Starting stopped instance: $INSTANCE_ID"
                aws ec2 start-instances --instance-ids $INSTANCE_ID
                aws ec2 wait instance-running --instance-ids $INSTANCE_ID
                echo "Instance started: $INSTANCE_ID"
            else
                echo "roboshop-$instance already running: $INSTANCE_ID"
            fi
        fi

        # Update Route53 record
        if [[ "$instance" == "frontend" ]]; then
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
            R53_RECORD="$DOMAIN_NAME"
        else
            IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text)
            R53_RECORD="$instance.$DOMAIN_NAME"
        fi

        if [[ -n "$IP" && "$IP" != "None" ]]; then
            aws route53 change-resource-record-sets \
            --hosted-zone-id $ZONE_ID \
            --change-batch "{
                \"Comment\": \"Update A record to new IP\",
                \"Changes\": [
                    {
                        \"Action\": \"UPSERT\",
                        \"ResourceRecordSet\": {
                            \"Name\": \"$R53_RECORD\",
                            \"Type\": \"A\",
                            \"TTL\": 1,
                            \"ResourceRecords\": [{\"Value\": \"$IP\"}]
                        }
                    }
                ]
            }"
            echo "Updated R53 record for: $instance"
        fi

    else
        # Delete action
        if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" || "$INSTANCE_ID" == "null" ]]; then
            echo "$instance already destroyed, nothing to do..."
        else
            STATE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                --query 'Reservations[0].Instances[0].State.Name' --output text)
            echo "Terminating Instance: $instance ($STATE)"
            aws ec2 terminate-instances --instance-ids $INSTANCE_ID
            aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID

            # Get IP BEFORE deletion for Route53
            if [[ "$instance" == "frontend" ]]; then
                R53_RECORD="$DOMAIN_NAME"
                IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                    --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
            else
                R53_RECORD="$instance.$DOMAIN_NAME"
                IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                    --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text)
            fi

            if [[ -n "$IP" && "$IP" != "None" ]]; then
                aws route53 change-resource-record-sets \
                --hosted-zone-id $ZONE_ID \
                --change-batch "{
                    \"Comment\": \"Delete A record\",
                    \"Changes\": [
                        {
                            \"Action\": \"DELETE\",
                            \"ResourceRecordSet\": {
                                \"Name\": \"$R53_RECORD\",
                                \"Type\": \"A\",
                                \"TTL\": 1,
                                \"ResourceRecords\": [{\"Value\": \"$IP\"}]
                            }
                        }
                    ]
                }"
                echo "Deleted R53 record for: $instance"
            fi
        fi
    fi
done