#!/bin/sh


# костыльный способ сделать BackUp VM в ESXi 
# ссылка на github https://github.com/NickNeoOne/bash-scripts


#Задаем переменные  даты времени и название лог файла
DATE=`date +"%m-%d-%y"`
TIME=`date +"%T"`
LOG_FILE=backup-$DATE.log

# Указываем ID виртуальной машины
VMID=3

# Указываем путь ОТКУДА бекапить
SOURCE_DIR=/vmfs/volumes/id_src_dir/

# Указываем путь КУДА бекапить
DEST_DIR=/vmfs/volumes/id_dst_dir/

# Указываем каталог где находятся файлы виртуальной машины (путь к ней /vmfs/volumes/e7d62437-0da87f64-0000-000000000000/)
VMNAME=SQUID



echo $DATE
echo $LOG_FILE
echo "=============== start log ===============" > /tmp/$LOG_FILE

# Проверяем наличие бекапа в каталоге DEST_DIR
if [ -z "$(ls -A ${DEST_DIR}${VMNAME})" ]; then
   echo "Empty dir ${DEST_DIR}${VMNAME}" >> /tmp/$LOG_FILE
   echo "do not delete old data" >> /tmp/$LOG_FILE
else
echo "REMOVE old VM backup" $DATE $TIME >> /tmp/$LOG_FILE

# Удаляем старый Бекап
rm -rf ${DEST_DIR}${VMNAME}_OLD

echo "move VM backup to OLD" $DATE $TIME >> /tmp/$LOG_FILE

# Переименовываем текущий бекап в старый
mv ${DEST_DIR}${VMNAME} ${DEST_DIR}${VMNAME}_OLD

fi

echo " " >> /tmp/$LOG_FILE
echo "Start BackUp VM" $DATE $TIME >> /tmp/$LOG_FILE

vim-cmd vmsvc/power.shutdown ${VMID}

# Функция проверки состояния VM
check_vm_status (){
var1=`vim-cmd vmsvc/power.getstate $VMID | grep Powered`
}

# Цикл проверки состояния VM
i=0
while check_vm_status
do
i=$(($i + 1))
if [ "$var1" == "Powered on" ]; then
	if [ "$i" -gt "20" ]; then
		echo "VM falied normal stop. FORCED stop !!!" >> /tmp/$LOG_FILE
		vim-cmd vmsvc/power.off $VMID
		sleep 10s
		break
	fi
 echo $i
 echo "WARNING: VM not stopped yet, waiting 1m " >> /tmp/$LOG_FILE
 sleep 1m
 else
 echo "VM normal stopped" $DATE $TIME >> /tmp/$LOG_FILE
 break
fi
done

# Запускаем копирование
cp -r ${SOURCE_DIR}${VMNAME}/ ${DEST_DIR} 2>> /tmp/$LOG_FILE

# Проверяем статус выполнения
STATUS=$?
if [[ $STATUS != 0 ]]; then
    echo " " >> /tmp/$LOG_FILE
    echo "VM copy ERROR!!! - " $DATE $TIME  >> /tmp/$LOG_FILE
else
    # Если все ОК
    echo " " >> /tmp/$LOG_FILE
    echo "VM copy completed - " $DATE $TIME  >> /tmp/$LOG_FILE
    echo " " >> /tmp/$LOG_FILE
    # узнаем размер скопированных файлов.
    VM_SIZE=`du -h ${DEST_DIR}${VMNAME} | awk '{ print $1}'`
    echo "VM copy size - " $VM_SIZE  >> /tmp/$LOG_FILE
    echo "starting VM  - " $DATE $TIME  >> /tmp/$LOG_FILE
fi 

# Запускаем VM
vim-cmd vmsvc/power.on ${VMID} 2>> /tmp/$LOG_FILE

# Проверяем статус выполнения
    STATUS=$?
if [[ $STATUS != 0 ]]; then
     echo " " >> /tmp/$LOG_FILE
     echo "start  VM ERROR - " $DATE $TIME  >> /tmp/$LOG_FILE
else
        # Если все ОК
     echo " " >> /tmp/$LOG_FILE
     echo "start  VM  - " $DATE $TIME  >> /tmp/$LOG_FILE
         
fi

echo "=============== end log ===============" >> /tmp/$LOG_FILE

# Копируем лог в указанную папку
mkdir -p ${DEST_DIR}log/
mv -f /tmp/$LOG_FILE ${DEST_DIR}log/

exit
