#!/bin/bash
# ссылка на github https://github.com/NickNeoOne/bash-scripts
# 
#
##########################################
#### ПЕРЕМЕННЫЕ ПОЛЬЗОВАТЕЛЯ
##########################################

# определяем Имя файла
FILE_NAME_FULL=`hostname`-full
FILE_NAME_INCR=`hostname`-increment

# Файл с путями которые не надо включать в архив
EXCLUDE_DIR=/opt/tar-gz.exclude

# Определяем день недели когда делать полный бекап (в формате 1 - понедельник, 2, 3 ... 7 - воскресенье)
date_full_backup=6

# Определяем текущую дату (число)
date_current=`date '+%u'`

# каталог монтирования SMB шары
SMB_SHARE="//SMB_SHARE/F$"
MOUNT_POINT="/mnt/smb/"

# каталоги которые будем бекапить можно указать несколько каталогов как указано ниже каждыйкаталог с новой строки.
#например:
    #TGTD2="/opt/dir1/
        #/mnt/smb1"
SOURCE_PATCH="/"

#полный путь к файлу с логином паролем
CREDENTIAL_DIR="/home/username/.smbclient"


# Каталог куда сохраняется  бекап
TARGET_DIR="/mnt/smb/`hostname`"

# Лог файл
LOGFILE=/var/log/backup-`hostname`.log
LOGFILE_ERROR=/var/log/backup-`hostname`-error.log
# Кому отправлять уведомление
MAIL_TO="usesr1@host.ru user2@host.ru"

# Кому отправлять копию уведомления
MAIL_TOCC=user3@host.ru

# От кого будем отправлять почту
MAIL_FROM=backup@host.ru

# Указываем адрес и порт почтового сервера
MAIL_SERVER=localhost
MAIL_PORT=25


##########################################
#### ПЕРЕМЕННЫЕ ПОЛЬЗОВАТЕЛЯ закончились
##########################################
HOST_NAME=$(hostname -f)

## Проверка переменных
exec 1>${LOGFILE}
exec 2>${LOGFILE_ERROR}
echo  "======================= begin backup ${HOST_NAME} $(date +'%d-%b-%Y %R') ==========================="
echo "Mail-TO кому:            " ${MAIL_TO}
echo "Mail-TOCC копия:         " ${MAIL_TOCC}
echo "Mail-FROM от кого:       " ${MAIL_FROM}
echo "Mail server:             " ${MAIL_SERVER}
echo "Mail port:               " ${MAIL_PORT}
echo "путь к файлу с логином:  " ${CREDENTIAL_DIR}
echo "Лог файл:                " ${LOGFILE}
echo "дата полного бекапа:     " ${date_full_backup}
echo "текущая дата :           " ${date_current}
echo "каталоги  для бекапа:    " ${SOURCE_PATCH}


#Монтируем SMB шару
if mountpoint -q ${MOUNT_POINT}
then
   echo "SMB шара:                " ${SMB_SHARE}
   echo "точка монтирования:      " ${MOUNT_POINT}
   echo "статус:                   mounted"
   MOUNT_SIZE=$(df -h | egrep "/mnt/smb" | awk '{print $2}')
   MOUNT_USED=$(df -h | egrep "/mnt/smb" | awk '{print $3}')
   echo "занято:                  " ${MOUNT_USED} "из:" ${MOUNT_SIZE}
else
   echo ${SMB_SHARE} "не была подключена, производим подключение"
   mount -t cifs -o rw,file_mode=0666,credentials=${CREDENTIAL_DIR} ${SMB_SHARE} ${MOUNT_POINT}
   # Проверяем статус бекапа
    STATUS_MOUNT=$?

    #echo ${STATUS_MOUNT} "статус команды монтирования"

    if [[ ${STATUS_MOUNT} != 0 ]];
    then
     #Если бекап не удался посылаем уведомление об этом на почту
     echo  "ОШИБКА! не удалось примотнировать " ${SMB_SHARE} ", выход..."

     sendEmail -f "${MAIL_FROM}"  -t "${MAIL_TO}" -cc "${MAIL_TOCC}"  -u backup "${HOST_NAME}" ERROR -s "${MAIL_SERVER}":"${MAIL_PORT}"  -o message-charset=UTF-8 -o message-file="${LOGFILE}"
     exit
    else
     echo "подключение прошло успешно."
   MOUNT_SIZE=$(df -h | egrep "/mnt/smb" | awk '{print $3}')
   MOUNT_USED=$(df -h | egrep "/mnt/smb" | awk '{print $3}')
   echo "занято:"  ${MOUNT_USED} "из:" ${MOUNT_SIZE}
    fi
fi

#echo "еще статус команды монтирования" ${STATUS}

# Есть проблема в том что если указывать в параметрах команд (напр. tar) имена каталогов с пробелами, скрипт срабатывает с ошибкой.
#Решение найдено на просторах интернета — операционная система linux использует пробел в качестве стандартного разделителя параметров команды.
#Переопределим стандартный разделитель (хранится в переменной $IFS) отличным от пробела, например \n – знаком переноса строки.
#Запоминаем старое значение стандартного разделителя
OLD_IFS=${IFS}

# Заменяем стандартный разделитель своим
IFS=$'\n'


# проверяем какой бекап зкапускать полный или инкрементный, если текущая дата не равна переменной date_full_backup то:
if [[ ${date_full_backup} != ${date_current} ]]; then
    # Запускаем инкрементный бекап
    echo "Задание " ${FILE_NAME_INCR} " запущено..."
    # Провеяем существование каталога, если нет создаем
    if ! [ -d ${TARGET_DIR}/inc/ ]; then
     echo 'No directory, create'
     mkdir -p ${TARGET_DIR}/inc/
    fi
    # Имя архива
    OUTPUT_FILE=${FILE_NAME_INCR}-`date '+%F-%H_%M_%S'`.tar.gz
    #tar pczvf  ${TARGET_DIR}/inc/${OUTPUT_FILE}  ${SOURCE_PATCH}  --listed-incremental ${TARGET_DIR}/${FILE_NAME_FULL}-log.snar
    tar pczvf   ${TARGET_DIR}/inc/${OUTPUT_FILE}  ${SOURCE_PATCH} -X ${EXCLUDE_DIR} --listed-incremental ${TARGET_DIR}/${FILE_NAME_FULL}-log.snar --warning=no-file-changed --warning=no-file-removed 1> /dev/null

    # Проверяем статус бекапа
    STATUS=$?

    # Возвращаем стандартный разделитель к исходному значению
    IFS=${OLD_IFS}
 
    if [[ ${STATUS} != 0 ]]; then
    #Если бекап не удался посылаем уведомление об этом на почту

        #rm -f ${TARGET_DIR}/inc/${OUTPUT_FILE} &
        echo "+=================================================================+"
        echo "  Произошла ошибка! Бэкап не удался.    "
        echo "+=================================================================+"
        BACKUP_STATUS="${FILE_NAME_INCR} ERROR"
        echo " "
        echo "Лог ошибок, для анализа:"
        echo " "
        cat ${LOGFILE_ERROR} >> ${LOGFILE}

    else
    # Если все ОК посылаем уведомление с подробновстями на почту
        echo "+=================================================================+"
        echo "   Сегодня $date_current день недели делаем Инкрементный бекап.   "
        echo "   Полный бекап произв-ся в $date_full_backup день недели         "
        echo "+=================================================================+"
        echo "Файл бэкапа сохранен как \"${TARGET_DIR}/inc/${OUTPUT_FILE}\" с размером `ls -lh  ${TARGET_DIR}/inc/${OUTPUT_FILE} | awk '{print ($5)}'`byte "
        echo " "
        echo  "================================ end backup ${HOST_NAME} ===================================="
        echo " "
        echo "Бэкап успешно выполнен в $(date +'%R %d-%b-%Y')"
        echo " "
        BACKUP_STATUS="${FILE_NAME_INCR} OK"
    fi
else
    # Иначе запускаем полный бекап
    echo "Задание \"${FILE_NAME_FULL}\" запущено..."
    # Провеяем существование каталога old, если нет создаем
    if ! [ -d ${TARGET_DIR}/old/ ]; then
     echo 'No directory, create'
     mkdir -p ${TARGET_DIR}/old/
    fi

    # Провеяем существование каталога Full, если нет создаем
        if ! [ -d ${TARGET_DIR}/Full/ ]; then
         echo 'No directory, create'
         mkdir -p ${TARGET_DIR}/Full/
        fi

    # Удаляем старый бекап
        rm ${TARGET_DIR}/old/*
        #echo ${TARGET_DIR}/old/${FILE_NAME_FULL}*
        #rm  ${TARGET_DIR}/old/${FILE_NAME_INCR}*
    #Перемещаем текущие бекапы в папку старых бекапов
        mv ${TARGET_DIR}/Full/* ${TARGET_DIR}/old/
        mv ${TARGET_DIR}/inc/* ${TARGET_DIR}/old/
        mv ${TARGET_DIR}/${FILE_NAME_FULL}-log.snar ${TARGET_DIR}/old/
        MOVE_STATUS=$?
        OUTPUT_FILE=${FILE_NAME_FULL}-`date '+%F-%H_%M_%S'`.tar.gz
        #echo "статус команды mv "${MOVE_STATUS}
        tar pczf   ${TARGET_DIR}/Full/${OUTPUT_FILE}  ${SOURCE_PATCH} -X ${EXCLUDE_DIR} --listed-incremental ${TARGET_DIR}/${FILE_NAME_FULL}-log.snar --warning=no-file-changed --warning=no-file-removed 1> /dev/null

        STATUS=$?
        IFS=${OLD_IFS}
        echo "статус команды tar "${STATUS}

    if [[ ${STATUS} != 0 ]]; then
        #rm -f ${TARGET_DIR}/Full/${OUTPUT_FILE} &
        echo "+=================================================================+"
        echo "  Произошла ошибка! Бэкап не удался.    "
        echo "+=================================================================+"
        echo " "
        BACKUP_STATUS="${FILE_NAME_INCR} ERROR"
        echo " "
        echo "Лог ошибок, для анализа:"
        echo " "
        cat ${LOGFILE_ERROR} >> ${LOGFILE}

    else
        # Имя архива
        echo "+=================================================================+"
        echo "    Сегодня  $date_current  день недели делаем  Полный бекап .   "
        echo "+=================================================================+"
        echo "Файл бэкапа сохранен как \"${TARGET_DIR}/Full/${OUTPUT_FILE}\" с размером `ls -lh  ${TARGET_DIR}/Full/${OUTPUT_FILE} | awk '{print ($5)}'`byte "
        echo " "
        echo  "================================ end backup ${HOST_NAME} ===================================="
        echo " "
        echo "Бэкап успешно выполнен в $(date +'%R %d-%b-%Y')"
        BACKUP_STATUS="${FILE_NAME_INCR} OK"
    fi

fi
        #    IFS=$OLD_IFS
        #
        sendEmail -f "${MAIL_FROM}"  -t ${MAIL_TO} -cc "${MAIL_TOCC}"  -u backup "${HOST_NAME}" "${BACKUP_STATUS}" -s "${MAIL_SERVER}":"${MAIL_PORT}"  -o message-charset=UTF-8 -o message-file="${LOGFILE}" 1> /dev/null
exit
