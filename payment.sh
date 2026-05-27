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

dnf install python3 gcc python3-devel -y &>>$LOGFILE

VALIDATE $? "install python"

id roboshop &>>$LOGFILE
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

curl -L -o /tmp/payment.zip https://roboshop-artifacts.s3.amazonaws.com/payment-v3.zip &>>$LOGFILE
VALIDATE $? "download code"

cd /app 
unzip /tmp/payment.zip &>>$LOGFILE

VALIDATE $? "unzip code"

cd /app  &>>$LOGFILE
pip3 install -r requirements.txt &>>$LOGFILE
VALIDATE $? "install pip packages"

cp -r payment.service  /etc/systemd/system/ &>>$LOGFILE
VALIDATE $? "copy user service"

systemctl daemon-reload &>>$LOGFILE
systemctl enable payment  &>>$LOGFILE
systemctl start payment &>>$LOGFILE
VALIDATE $? "enabe and start service"