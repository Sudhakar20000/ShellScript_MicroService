#!/bin/bash
LOGDIR=/var/log/roboshop_log
LOGFILE=$LOGDIR/$0.sh
mkdir -p /var/log/roboshop_log
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

VALIDATE $? "enable nodejs20"

dnf install nodejs -y

VALIDATE $? "install nodejs"
id roboshop
if [ $? -ne 0]
 useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop
 VALIDATE $? "useradded"
 else 
 echo -e "user already exist $Y SKPPING $N"
fi

rm -rf /app  &>>$LOGS_FILE
rm -rf /tmp/catalogue.zip  &>>$LOGS_FILE
VALIDATE $? "removing existing directorys"

mkdir -R /app  &>>$LOGS_FILE
curl -o /tmp/catalogue.zip https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip   &>>$LOGS_FILE
VALIDATE $? " create and download code"

cd /app   &>>$LOGS_FILE
unzip /tmp/catalogue.zip  &>>$LOGS_FILE
VALIDATE $? "unzip the code"

cd /app   &>>$LOGS_FILE
npm install  &>>$LOGS_FILE
VALIDATE $? "install npm packages"

cp -r $SCRIPI_DIR/catalogue.service /etc/systemd/system/
VALIDATE $? "created service file"

systemctl daemon-reload
systemctl enable --now catalogue
VALIDATE $? "demon reload and start catalog"

cp -r $SCRIPI_DIR/mongo.repo /etc/yum.repos.d/mongo.repo
VALIDATE $? "added mongo repo"

dnf install mongodb-mongosh -y
VALIDATE $? "install mongoclint"


INDEX=$(mongosh --host mongodb.sudhakar.shop --eval 'db.getMongo().getDBNames().indexOf("catalogue")')

if [ $INDEX -lt 0 ]; then
    mongosh --host mongodb.sudhakar.shop </app/db/master-data.js &>>$LOGS_FILE
    VALIDATE $? "Load Products"
else
    echo -e "Products already loaded ... $Y SKIPPING $N"
fi

systemctl enable catalogue &>>$LOGS_FILE
systemctl restart catalogue &>>$LOGS_FILE
VALIDATE $? "Restarting catalogue"





