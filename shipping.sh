#!/bin/bash
LOGDIR=/var/log/roboshop_log
LOGFILE=$LOGDIR/$0.log
mkdir -p $LOGDIR
chmod -R 755 $LOGDIR
chown -R ec2-user:ec2-user $LOGDIR
USERID=$(id -u)
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
TIME_STAMP=$(date '+%Y-%m-%d %H:%M:%S')
MYSQL_HOST=mysql.sudhakar.shop
if [ $USERID -ne 0 ]; then
  echo -e "$TIME_STAMP [ERROR] $R switch to root user $N" | tee -a $LOGFILE
  exit 1
fi

VALIDATE() {
    if [ $1 -ne 0 ]; then
    echo -e "$TIME_STAMP [ERROR] $R error on $2 $N" | tee -a $LOGFILE
    exit 1
    else
    echo -e "$TIME_STAMP [INFO] $G success for $2 $N" | tee -a $LOGFILE
fi
}

dnf install maven -y
VALIDATE $? "install maven" &>>$LOGFILE

id roboshop
if [ $? -eq 0 ]; then
 echo -e "$TIME_STAMP the user exists $Y skpping.. $N" | tee -a $LOGFILE
 else
 useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop  &>>$LOGFILE
 echo -e "$TIME_STAMP [INFO] $G user created $N" | tee -a $LOGFILE
fi

mkdir -p /app 
curl -L -o /tmp/shipping.zip https://roboshop-artifacts.s3.amazonaws.com/shipping-v3.zip  &>>$LOGFILE
cd /app 
unzip /tmp/shipping.zip  &>>$LOGFILE

VALIDATE $? " app directory creat and unzip"

cd /app 
mvn clean package   &>>$LOGFILE 
VALIDATE $? "mvn clean package"

mv target/shipping-1.0.jar shipping.jar &>>$LOGFILE
VALIDATE $? "rename jar"

VALIDATE $? "mvn clean package"

cp -r shipping.service /etc/systemd/system/  &>>$LOGFILE
VALIDATE $? "service copy"

systemctl daemon-reload  &>>$LOGFILE
systemctl enable shipping   &>>$LOGFILE
systemctl start shipping  &>>$LOGFILE
VALIDATE $? "restart compleate"

dnf install mysql -y 

VALIDATE $? "install mysql"

mysql -h $MYSQL_HOST -u root -pRoboShop@1 -e "use cities" &>>$LOGFILE
if [ $? -ne 0 ]; then
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/schema.sql
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/app-user.sql
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 < /app/db/master-data.sql
    VALIDATE $? "Data loaded"
else
    echo -e "Data already loaded ... $Y SKIPPING $N"
fi

systemctl enable shipping &>>$LOGFILE
systemctl restart shipping &>>$LOGFILE
VALIDATE $? "Enable and restarted shipping"


