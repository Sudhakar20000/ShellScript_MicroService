#!/bin/bash

LOGDIR=/var/log/roboshop_log
LOGFILE=$LOGDIR/catalogue.log

mkdir -p $LOGDIR
chmod -R 755 $LOGDIR
chown -R ec2-user:ec2-user $LOGDIR

SCRIPI_DIR=$PWD

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

USERID=$(id -u)
TIME_STAMP=$(date '+%Y-%m-%d %H:%M:%S')

if [ $USERID -ne 0 ]; then
  echo -e "$TIME_STAMP [ERROR] ${R}switch to root user${N}" | tee -a $LOGFILE
  exit 1
fi

VALIDATE () {
    if [ $1 -ne 0 ]; then
        echo -e "$TIME_STAMP [ERROR] ${R}error for $2${N}" | tee -a $LOGFILE
        exit 1
    else
        echo -e "$TIME_STAMP [INFO] ${G}success for $2${N}" | tee -a $LOGFILE
    fi
}

dnf module disable nodejs -y &>>$LOGFILE
dnf module enable nodejs:20 -y &>>$LOGFILE
VALIDATE $? "Enable NodeJS 20"

dnf install nodejs -y &>>$LOGFILE
VALIDATE $? "Install NodeJS"

id roboshop &>>$LOGFILE
if [ $? -ne 0 ]; then
    useradd --system --home /app --shell /sbin/nologin \
    --comment "roboshop system user" roboshop
    VALIDATE $? "User added"
else
    echo -e "user already exists $Y SKIPPING $N"
fi

rm -rf /app &>>$LOGFILE
rm -rf /tmp/catalogue.zip &>>$LOGFILE
VALIDATE $? "Clean old files"

mkdir -p /app &>>$LOGFILE

curl -o /tmp/catalogue.zip \
https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip &>>$LOGFILE
VALIDATE $? "Download code"

cd /app &>>$LOGFILE
unzip /tmp/catalogue.zip &>>$LOGFILE
VALIDATE $? "Unzip code"

cd /app &>>$LOGFILE
npm install &>>$LOGFILE
VALIDATE $? "Install npm packages"

cp -r $SCRIPI_DIR/catalogue.service /etc/systemd/system/
VALIDATE $? "Copy service file"

systemctl daemon-reload &>>$LOGFILE
systemctl enable --now catalogue &>>$LOGFILE
VALIDATE $? "Start catalogue service"

cp -r $SCRIPI_DIR/mongo.repo /etc/yum.repos.d/mongo.repo
VALIDATE $? "Add Mongo repo"

dnf install mongodb-mongosh -y &>>$LOGFILE
VALIDATE $? "Install Mongo client"

INDEX=$(mongosh --host mongodb.sudhakar.shop --quiet --eval 'db.getMongo().getDBNames().indexOf("catalogue")')

if [ "$INDEX" -lt 0 ]; then
    mongosh --host mongodb.sudhakar.shop </app/db/master-data.js &>>$LOGFILE
    VALIDATE $? "Load Products"
else
    echo -e "Products already loaded ... $Y SKIPPING $N"
fi

systemctl restart catalogue &>>$LOGFILE
VALIDATE $? "Restart catalogue"