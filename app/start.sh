#! /bin/bash

echo "Preparing the system for a check..."
# Create a symlinc to the folder with VM extention logs, so we can
# validate that azure monitor agent is sending metrics by checking
# the Azure Monitor Agend log /var/opt/microsoft/azuremonitoragent/log/mdsd.info
ln -s  /var/opt/microsoft /app/todolist/static/files

lsblk -o NAME,HCTL,SIZE,MOUNTPOINT > /data/app/todolist/static/files/task3.log

pip install -r requirements.txt
python3 manage.py migrate
python3 manage.py runserver 0.0.0.0:8080

##!/bin/bash
#
#echo "Preparing the system for a check..."
## Create a symlinc to the folder with VM extention logs, so we can
## validate that azure monitor agent is sending metrics by checking
## the Azure Monitor Agend log /var/opt/microsoft/azuremonitoragent/log/mdsd.info
#
#if [ ! -d "/data/app/todolist/static/files" ]; then
#    echo "Директория /data/app/todolist/static/files не существует. Создаём..."
#    sudo mkdir -p /data/app/todolist/static/files
#    sudo chmod -R 755 /data/app/todolist/static/files
#fi
#
#if [ ! -d "/var/opt/microsoft" ]; then
#    echo "Директория /var/opt/microsoft не существует. Создаём..."
#    sudo mkdir -p /var/opt/microsoft
#    sudo chmod -R 755 /var/opt/microsoft
#fi
#
#ln -s  /var/opt/microsoft /data/app/todolist/static/files
#
#lsblk -o NAME,HCTL,SIZE,MOUNTPOINT > /data/app/todolist/static/files/task3.log
#cd /data/app
#pip install -r requirements.txt
#python3 manage.py migrate
#python3 manage.py runserver 0.0.0.0:8080