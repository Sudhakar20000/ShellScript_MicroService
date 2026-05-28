#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z03774782PWBJZ4CLRX9V"
DOMAIN_NAME="sudhakar.shop"

# =========================
# GET INSTANCE ID
# =========================
get_instance_id() {
    local name=$1
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=roboshop-$name" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text 2>/dev/null
}

# =========================
# GET INSTANCE STATE
# =========================
get_instance_state() {
    local id=$1
    aws ec2 describe-instances \
        --instance-ids "$id" \
        --query "Reservations[0].Instances[0].State.Name" \
        --output text 2>/dev/null
}

# =========================
# GET SG ID
# =========================
get_sg() {
    local name=$1
    aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=$name" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null
}

# =========================
# GET ROUTE53 RECORD IP
# =========================
get_r53_ip() {
    local r53_name=$1
    aws route53 list-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --query "ResourceRecordSets[?Name=='${r53_name}.'].ResourceRecords[0].Value" \
        --output text 2>/dev/null
}

# =========================
# DELETE ACTION
# =========================
do_delete() {
    local instance=$1
    local SG_NAME="roboshop-$instance"
    local IP R53 SG_ID INSTANCE_ID

    # Determine R53 name
    if [[ "$instance" == "frontend" ]]; then
        R53="$DOMAIN_NAME"
    else
        R53="$instance.$DOMAIN_NAME"
    fi

    echo "=============================="
    echo "DELETE: $instance"
    echo "=============================="

    # STEP 1: CHECK + TERMINATE INSTANCE
    INSTANCE_ID=$(get_instance_id "$instance")
    if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
        echo "[INSTANCE] Not found — already deleted or never created"
    else
        echo "[INSTANCE] Found: $INSTANCE_ID — terminating..."

        # Capture IP before termination
        if [[ "$instance" == "frontend" ]]; then
            IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        else
            IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
        fi

        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" > /dev/null
        echo "[INSTANCE] Waiting for termination..."
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
        echo "[INSTANCE] Terminated: $INSTANCE_ID"
    fi

    # STEP 2: CHECK + DELETE ROUTE53
    EXISTING_IP=$(get_r53_ip "$R53")
    if [[ -z "$EXISTING_IP" || "$EXISTING_IP" == "None" ]]; then
        echo "[ROUTE53]  Record not found — already deleted or never created: $R53"
    else
        # Use captured IP if available, else use the one from Route53
        RECORD_IP="${IP:-$EXISTING_IP}"
        aws route53 change-resource-record-sets \
            --hosted-zone-id "$ZONE_ID" \
            --change-batch "{
                \"Comment\": \"DELETE record\",
                \"Changes\": [{
                    \"Action\": \"DELETE\",
                    \"ResourceRecordSet\": {
                        \"Name\": \"$R53\",
                        \"Type\": \"A\",
                        \"TTL\": 1,
                        \"ResourceRecords\": [{\"Value\": \"$RECORD_IP\"}]
                    }
                }]
            }" 2>/dev/null
        echo "[ROUTE53]  Deleted: $R53 → $RECORD_IP"
    fi

    # STEP 3: CHECK + DELETE SECURITY GROUP
    SG_ID=$(get_sg "$SG_NAME")
    if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
        echo "[SG]       Not found — already deleted or never created: $SG_NAME"
    else
        # Verify no instances are still using this SG
        IN_USE=$(aws ec2 describe-instances \
            --filters "Name=instance.group-id,Values=$SG_ID" \
                      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
            --query "Reservations[]" \
            --output text 2>/dev/null)
        if [[ -n "$IN_USE" ]]; then
            echo "[SG]       Still in use — skipping delete: $SG_NAME ($SG_ID)"
        else
            aws ec2 delete-security-group --group-id "$SG_ID"
            echo "[SG]       Deleted: $SG_NAME ($SG_ID)"
        fi
    fi

    echo "[DONE]     DELETE complete: $instance"
    echo ""
}

# =========================
# CREATE ACTION
# =========================
do_create() {
    local instance=$1
    local SG_NAME="roboshop-$instance"
    local IP R53 SG_ID INSTANCE_ID

    # Determine R53 name
    if [[ "$instance" == "frontend" ]]; then
        R53="$DOMAIN_NAME"
    else
        R53="$instance.$DOMAIN_NAME"
    fi

    echo "=============================="
    echo "CREATE: $instance"
    echo "=============================="

    # STEP 1: CHECK + CREATE SECURITY GROUP
    SG_ID=$(get_sg "$SG_NAME")
    if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
        echo "[SG]       Already exists: $SG_NAME ($SG_ID)"
    else
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "Security group for roboshop-$instance" \
            --query "GroupId" --output text)
        echo "[SG]       Created: $SG_NAME ($SG_ID)"
    fi

    # STEP 2: CHECK + CREATE INSTANCE
    INSTANCE_ID=$(get_instance_id "$instance")
    if [[ -n "$INSTANCE_ID" && "$INSTANCE_ID" != "None" ]]; then
        echo "[INSTANCE] Already exists: $INSTANCE_ID (state: $(get_instance_state "$INSTANCE_ID"))"
    else
        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --instance-type t3.micro \
            --security-group-ids "$SG_ID" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
            --query "Instances[0].InstanceId" \
            --output text)
        echo "[INSTANCE] Created: $INSTANCE_ID — waiting for running state..."
        aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
        echo "[INSTANCE] Running: $INSTANCE_ID"
    fi

    # STEP 3: GET IP
    if [[ "$instance" == "frontend" ]]; then
        IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    else
        IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
    fi

    # STEP 4: CHECK + CREATE ROUTE53
    EXISTING_IP=$(get_r53_ip "$R53")
    if [[ -n "$EXISTING_IP" && "$EXISTING_IP" != "None" ]]; then
        echo "[ROUTE53]  Record already exists: $R53 → $EXISTING_IP"
        if [[ "$EXISTING_IP" != "$IP" ]]; then
            echo "[ROUTE53]  IP changed ($EXISTING_IP → $IP) — updating..."
            aws route53 change-resource-record-sets \
                --hosted-zone-id "$ZONE_ID" \
                --change-batch "{
                    \"Comment\": \"UPSERT record\",
                    \"Changes\": [{
                        \"Action\": \"UPSERT\",
                        \"ResourceRecordSet\": {
                            \"Name\": \"$R53\",
                            \"Type\": \"A\",
                            \"TTL\": 1,
                            \"ResourceRecords\": [{\"Value\": \"$IP\"}]
                        }
                    }]
                }" > /dev/null
            echo "[ROUTE53]  Updated: $R53 → $IP"
        fi
    else
        aws route53 change-resource-record-sets \
            --hosted-zone-id "$ZONE_ID" \
            --change-batch "{
                \"Comment\": \"CREATE record\",
                \"Changes\": [{
                    \"Action\": \"CREATE\",
                    \"ResourceRecordSet\": {
                        \"Name\": \"$R53\",
                        \"Type\": \"A\",
                        \"TTL\": 1,
                        \"ResourceRecords\": [{\"Value\": \"$IP\"}]
                    }
                }]
            }" > /dev/null
        echo "[ROUTE53]  Created: $R53 → $IP"
    fi

    echo "[DONE]     CREATE complete: $instance (IP: $IP)"
    echo ""
}

# =========================
# MAIN
# =========================
ACTION=$1
shift

if [[ -z "$ACTION" || -z "$1" ]]; then
    echo "Usage: $0 <create|delete> <instance1> [instance2] ..."
    echo "Example: $0 create frontend cart user"
    echo "         $0 delete frontend cart user"
    exit 1
fi

for instance in "$@"; do
    case "$ACTION" in
        create) do_create "$instance" ;;
        delete) do_delete "$instance" ;;
        *)
            echo "Unknown action: $ACTION (use create or delete)"
            exit 1
            ;;
    esac
done