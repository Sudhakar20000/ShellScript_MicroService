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

dnf module disable nodejs -y &>>$LOGFILE
dnf module enable nodejs:20 -y &>>$LOGFILE

VALIDATE $? "enable nodejs"

dnf install nodejs -y &>>$LOGFILE
VALIDATE $? "install nodejs"

id roboshop   &>>$LOGFILE
if [ $? -eq 0 ]; then
 echo -e "$TIME_STAMP the user exists $Y skpping.. $N" | tee -a $LOGFILE
 else
 useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop  &>>$LOGFILE
 echo -e "$TIME_STAMP [INFO] $G user created $N" | tee -a $LOGFILE
fi

rm -rf /app  &>>$LOGFILE
rm -rf /tmp/user.zip  &>>$LOGFILE
VALIDATE $? "delete existing dir"

mkdir -p /app &>>$LOGFILE

curl -L -o /tmp/user.zip https://roboshop-artifacts.s3.amazonaws.com/cart-v3.zip &>>$LOGFILE
VALIDATE $? "download code"

cd /app  &>>$LOGFILE
unzip /tmp/user.zip &>>$LOGFILE

VALIDATE $? "unzip code"
 
cd /app  &>>$LOGFILE
npm install &>>$LOGFILE
VALIDATE $? "install npm packages"

cp -r user.service  /etc/systemd/system/cart.service
VALIDATE $? "copy cart service"

systemctl daemon-reload &>>$LOGFILE
systemctl enable cart  &>>$LOGFILE
systemctl start cart &>>$LOGFILE
VALIDATE $? "enabe and start service"