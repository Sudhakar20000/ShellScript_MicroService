#!/bin/bash

LOGDIR=/var/log/roboshop_log
mkdir -p "$LOGDIR"

LOGFILE="$LOGDIR/$(basename "$0").log"

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

TIME_STAMP=$(date '+%Y-%m-%d %H:%M:%S')

USERID=$(id -u)

if [ "$USERID" -ne 0 ]; then
  echo -e "$TIME_STAMP [ERROR] $R switch to root user $N" | tee -a "$LOGFILE"
  exit 1
fi

chmod -R 755 "$LOGDIR"
chown -R ec2-user:ec2-user "$LOGDIR"

VALIDATE () {
    if [ "$1" -ne 0 ]; then
        echo -e "$TIME_STAMP [ERROR] $R error for $2 $N" | tee -a "$LOGFILE"
        exit 1
    else
        echo -e "$TIME_STAMP [INFO] $G success for $2 $N" | tee -a "$LOGFILE"
    fi
}

dnf module disable nodejs -y &>> "$LOGFILE"
dnf module enable nodejs:20 -y &>> "$LOGFILE"
VALIDATE $? "enable nodejs"

dnf install nodejs unzip -y &>> "$LOGFILE"
VALIDATE $? "install nodejs"

id roboshop &>> "$LOGFILE"

if [ $? -eq 0 ]; then
  echo -e "$TIME_STAMP [INFO] $Y user already exists skipping $N" | tee -a "$LOGFILE"
else
  useradd --system --home /app --shell /sbin/nologin roboshop &>> "$LOGFILE"
  echo -e "$TIME_STAMP [INFO] $G user created $N" | tee -a "$LOGFILE"
fi

mkdir -p /app

curl -L -o /tmp/user.zip https://roboshop-artifacts.s3.amazonaws.com/user-v3.zip
VALIDATE $? "download code"

cd /app || exit 1
unzip -o /tmp/user.zip &>> "$LOGFILE"
VALIDATE $? "unzip code"

npm install &>> "$LOGFILE"
VALIDATE $? "npm install"

SERVICE_FILE="/home/ec2-user/ShellScript_MicroService/user.service"

if [ -f "$SERVICE_FILE" ]; then
    cp "$SERVICE_FILE" /etc/systemd/system/user.service
else
    echo -e "$TIME_STAMP [ERROR] $R user.service not found $N" | tee -a "$LOGFILE"
    exit 1
fi

VALIDATE $? "copy service file"

systemctl daemon-reload &>> "$LOGFILE"

systemctl enable user &>> "$LOGFILE"
VALIDATE $? "enable service"

systemctl start user &>> "$LOGFILE"
VALIDATE $? "start service"