#!/bin/bash
# ссылка на github https://github.com/NickNeoOne/bash-scripts
# По умолчанию бекап БД не делается, чтобы запустить backup Базы данных необходимо качестве параметра передать значение "BD" 
# пример: /opt/backup-config.sh BD
#
##########################################
#### ПЕРЕМЕННЫЕ ПОЛЬЗОВАТЕЛЯ
##########################################

# Данные для подключения к БД
HOSTNAME=hostname-psql-server
USERNAME=username
DB_NAME=DB_name
export PGPASSWORD="PASSWORD"

# Каталог куда сохраняется бекап, в нем будет создан подкаталог в соответствии с датой бекапа
TARGET_DIR="/opt/backup/bd/`date '+%F'`/"
# определяем Имя файла

OUTPUT_FILE=${DB_NAME}-backup.psql.gz


# каталоги которые будем бекапить можно указать несколько каталогов как указано ниже каждый каталог с новой строки.
#например:
#TGTD2="/mnt/smb/
#/mnt/smb1"
SOURCE_PATCH="/etc/squid
/etc/default
/var/www/html
/usr/lib/squid
/etc/krb5.conf"


# Лог файл
LOGFILE="$TARGET_DIR"bd_backup.log

# Кому отправлять уведомление
MAIL_TO=user-to@email.ru

# Кому отправлять копию уведомления
MAIL_TOCC=user2-to@email2.ru

# От кого будем отправлять почту
MAIL_FROM=bd-backup@email.ru

# Указываем адрес и порт почтового сервера
#MAIL_SERVER=10.10.10.42
MAIL_SERVER=hostname.mail.server.ru

MAIL_PORT=25

echo "$HOSTNAME"
echo "$USERNAME"
echo "$DB_NAME"
echo "$TARGET_DIR""$OUTPUT_FILE"

mkdir -p "$TARGET_DIR"

echo "" >$LOGFILE

# Запускаем backup Базы данных если в качестве параметра получили значение BD иначе бекап БД не делаем
if [[ $1 == BD ]]; then

pg_dump -C -h "$HOSTNAME" -U "$USERNAME" "$DB_NAME" | gzip > "$TARGET_DIR""$OUTPUT_FILE"
#pg_dump -C -h "$HOSTNAME" -U "$USERNAME"  "$DB_NAME"   > "$TARGET_DIR""$OUTPUT_FILE".psql

# Проверяем статус бекапа БД
 if [ -s "$TARGET_DIR""$OUTPUT_FILE" ]
  then
        echo "Файл бэкапа сохранен как \"$TARGET_DIR$OUTPUT_FILE\" с размером `ls -lh  "$TARGET_DIR""$OUTPUT_FILE" | awk '{print ($5)}'`byte" >>$LOGFILE
        echo "Бэкап БД успешно выполнен в $(date +'%R %d-%b-%Y')" >>$LOGFILE
        echo "+-------------------------------------------------------------------------------------+" >>$LOGFILE
  else
        echo "+------------------------------------------------------------------+" >>$LOGFILE
        echo "|  Сегодня $(date +'%R %d-%b-%Y') Произошла ошибка! Бэкап БД не удался.    |" >>$LOGFILE
        echo "+------------------------------------------------------------------+" >>$LOGFILE
  fi

else
        echo "+-------------------------------------------------------------------------------------+" >>$LOGFILE
        echo "Бэкап БД не запускался так как не был указан параметр для этого" >>$LOGFILE
        echo "+-------------------------------------------------------------------------------------+" >>$LOGFILE
fi

# Очищаем переменную PGPASSWORD для безопасности
export PGPASSWORD=""

# Запускаем backup конфигурационных файлов
OUTPUT_DATAFILE=config-backup.tar.gz
tar pczvf  $TARGET_DIR$OUTPUT_DATAFILE  $SOURCE_PATCH

# Проверяем статус бекапа
STATUS=$?
if [[ $STATUS != 0 ]]; then
        echo "+------------------------------------------------------------------+" >>$LOGFILE
        echo "|  Сегодня $(date +'%R %d-%b-%Y') Произошла ошибка! Бэкап конфигурационных файлов не удался.    |" >>$LOGFILE
        echo "+------------------------------------------------------------------+" >>$LOGFILE
else
        echo "+-------------------------------------------------------------------------------------+" >>$LOGFILE
        echo "Файл бэкапа сохранен как \"$TARGET_DIR$OUTPUT_FILE\" с размером `ls -lh  "$TARGET_DIR""$OUTPUT_DATAFILE" | awk '{print ($5)}'`byte" >>$LOGFILE
        echo "Бэкап конфигурационных файлов  успешно выполнен в $(date +'%R %d-%b-%Y')" >>$LOGFILE
        echo "+-------------------------------------------------------------------------------------+" >>$LOGFILE
fi

# Если необходимо шлем уведомление в почту
# sendEmail -f "$MAIL_FROM"  -t "$MAIL_TO" -cc "$MAIL_TOCC"  -u backup "$BACKUP_STATUS" -s "$MAIL_SERVER":"$MAIL_PORT"  -o message-charset=UTF-8 -o message-file="$LOGFILE"
exit
