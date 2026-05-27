#!/bin/bash
LOGDIR=/var/log/roboshop_log
LOGFILE=$LOGDIR/$0.sh
mkdir -p /var/log/roboshop_log
chmod -R 755 $LOGDIR
chown -R ec2-user:ec2-user $LOGDIR
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
USERID=$(id -u)
TIME_STAMP=$(date '+%Y-%m-%d %H:%M:%S')
if [ $USERID -ne 0 ]; then
  echo -e "$TIME_STAMP [ERROR] $R switch to root user $N" | tee -a $LOGFILE 
  exit 1
fi
VALIDATE () {
    if [ $1 -ne 0 ]; then
    echo -e "$TIME_STAMP [error] $R error for $2 $N" | tee -a $LOGFILE
    exit 1
    else
    echo -e "$TIME_STAMP [INFO] $G success for $2 $N" | tee -a $LOGFILE
fi
}

dnf module disable nodejs -y
dnf module enable nodejs:20 -y

VALIDATE $? "enable nodejs"

dnf install nodejs -y
VALIDATE $? "install nodejs"

id roboshop
if [ $? -eq 0 ]; then
 echo -e "$TIME_STAMP the user exists $Y skpping.. $N" | tee -a $LOGFILE
 else
 useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop  &>>$LOGFILE
 echo -e "$TIME_STAMP [INFO] $G user created $N" | tee -a $LOGFILE
fi

mkdir -p /app

curl -L -o /tmp/user.zip https://roboshop-artifacts.s3.amazonaws.com/user-v3.zip
VALIDATE $? "download code"

cd /app 
unzip /tmp/user.zip

VALIDATE $? "unzip code"

cd /app 
npm install 
VALIDATE $? "install npm packages"

cp -r user.service  /etc/systemd/system/user.service
VALIDATE $? "copy user service"

systemctl daemon-reload
systemctl enable user 
systemctl start user
VALIDATE $? "enabe and start service"