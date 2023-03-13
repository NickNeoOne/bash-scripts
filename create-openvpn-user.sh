#!/bin/bash
# TUI для добавления генерации сертификатов для подключения 
# к серверу и отсылкой конфигурационного файла по e-mail
# должны быть установлены утилиты dialog и sendEmail
#
# Переменные для генерации сертификата пользователя
# сертификаты OpenVPN сервера
KEY_DIR=/etc/openvpn/keys/

# Выходной каталог пользовательского конфига
OUTPUT_DIR=/root/OpenVpn/users/

# базовый конфиг
BASE_CONFIG=/root/OpenVpn/base.conf

# Каталог скриптов утилиты easy-rsa
EASYRSA_DIR=/etc/openvpn/easy-rsa

HOST_NAME=$(hostname -f)

# Кому отправлять уведомление
MAIL_TO="admin@domail.com"


# От кого будем отправлять почту
MAIL_FROM="OpenVPN@domain.com"

# Указываем адрес и порт почтового сервера
MAIL_SERVER=smtp.mailserver.com
MAIL_PORT=25

USERNAME=$(dialog  --title "OpenVPN" --inputbox \
"Ведите имя пользователя (латиницей без пробелов)" 0 0  3>&1 1>&2 2>&3 3>&- )

# Проверка корректности если имя пользователя не задано выходим с ошибкой
if [ -z "$USERNAME" ];then
  clear
  echo -e "\n\033[31m Ошибка!!!\n\033[0m Не задано имя пользователя."
 exit
fi

USERNOTIFY=$(dialog --title "Уведомления пользователя"  --menu \
"Выслать пользователю конфигурационный файл на указанный email?"  0 0 0   \
"1" "Нет, не высылать" "2" "Да, выслать"   3>&1 1>&2 2>&3 3>&-) || USERNOTIFY=1


case $USERNOTIFY in
1) USERSENDMAIL="Нет"; USERMAIL="не указан" ;;
2) USERMAIL=$(dialog  --title "OpenVPN" --inputbox \
"Укажите Email пользователя " 0 0 3>&1 1>&2 2>&3 3>&- ); USERSENDMAIL="Да";;
esac

if [ -z "$USERMAIL" -a $USERNOTIFY == 2  ] ; then
  clear
  echo -e "\n\033[31m Ошибка!!!\n\033[0m Выбран пункт \"уведомить пользователя\", но не задан E-mail."
 exit
fi

dialog  --title "OpenVPN" --yesno "Проверка данных!
\n Имя пользователя: $USERNAME
\n E-mail пользователя: $USERMAIL
\n Уведомить пользователя: $USERSENDMAIL
\n\nдля продолжения выберите Yes(Да), для выхода No(Нет)" 0 0

exitstatus=$?
if [ $exitstatus != 0 ]; then
clear;
  echo -e "\n\033[42m Пользователь прервал выполнение скрипта.\n\033[0m"
exit;
fi




# Выполняем генерацию сертификатов
cd $EASYRSA_DIR
./easyrsa build-client-full $USERNAME nopass

#  Собираем конфиг файл пользователя
cat ${BASE_CONFIG} \
    <(echo -e '<ca>') \
    ${KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    /etc/openvpn/easy-rsa/pki/issued/${1}.crt \
    <(echo -e '</cert>\n<key>') \
    /etc/openvpn/easy-rsa/pki/private/${1}.key \
    <(echo -e '</key>\n') \
    > ${OUTPUT_DIR}/${1}.ovpn

# Прописываем дополнительные параметры передавемые пользователю
touch /etc/openvpn/client/$1
echo "push \"route 10.10.0.0 255.255.0.0\"" >> /etc/openvpn/client/$1
echo "push \"dhcp-option DNS 10.10.10.1\"" >> /etc/openvpn/client/$1
echo "push \"dhcp-option DNS 10.10.10.2\"" >> /etc/openvpn/client/$1

#Высылаем уведомление админу и пользователю если указано.
sendEmail -f "${MAIL_FROM}"  -t ${MAIL_TO} -cc "${USERMAIL}"  -u add NEW VPN-user "${1}" on server "${HOST_NAME}"  -s "${MAIL_SERVER}":"${MAIL_PORT}"  -o message-charset=UTF-8  -a "${OUTPUT_DIR}/${1}.ovpn" -m "Добавили пользователя ${1} на сервере ${HOST_NAME} "> /dev/null
