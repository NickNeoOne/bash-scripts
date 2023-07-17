#!/bin/bash

# Сетевые настройки
IP=172.19.1.10
GW=172.19.1.1
NAMESERVER=172.19.1.6
NETMASK=255.255.250.0

#Настройки домена
# Имя сервера
DC_NAME=dc1
# домен
DOMAIN=astradc.lan
# пароль админа
ADMIN_PWD=Passw0rd0123

# настройки прокси для apt, если закоментировано то не добавляются
#PROXY=http://172.19.1.1:8080/

CHEK_VERS=`astra-modeswitch get`

if [ "$CHEK_VERS" != 2 ]; then
            echo -e " \033[31m ОС Astra Linux  НЕ функционирует на максимальном уровне защищенности. Выход! \033[0m"
                exit
        fi
echo -e "\033[32m ОС Astra Linux  функционирует на максимальном уровне защищенности \033[0m"

if [ -z ${PROXY} ]; then
echo -e "\033[32m Не задана  переменная PROXY\033[0m apt будет работать без прокси, при необходимости заполните переменную PROXY"
else
        echo -e "\033[32m Задана переменная PROXY=$PROXY \033[0m добавляем настройки в apt для работы через прокси сервер "
cat > /etc/apt/apt.conf.d/02proxy <<EOF
Acquire::http::Proxy "$PROXY";
Acquire::https::Proxy "$PROXY";
EOF
fi

echo "удаляем network-manager"

systemctl stop network-manager
systemctl disable network-manager
apt remove network-manager-gnome -y

echo ""
echo "Правим сетевые настройки"
cp /etc/network/interfaces /etc/network/interfaces_backup_ald
cat > /etc/network/interfaces <<EOF

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address $IP
netmask $NETMASK
gateway $GW
dns-nameservers $NAMESERVER
dns-search $DOMAIN
EOF

echo ""
echo "Правим сетевые resolv.conf"

cat > /etc/resolv.conf <<EOF
nameserver $NAMESERVER
search $DOMAIN
EOF

echo ""
echo "Задаем имя сервера"

echo $DC_NAME.$DOMAIN > /etc/hostname

hostnamectl set-hostname $DC_NAME.$DOMAIN

cat > /etc/hosts <<EOF
127.0.0.1     localhost.localdomain localhost
$IP  $DC_NAME.$DOMAIN $DC_NAME
127.0.1.1     $DC_NAME

::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

echo ""
echo "Рестарт сетевых интерфейсов для применения настроек"
systemctl restart networking

echo ""
echo "Добавляем репозитарии"

cp /etc/apt/sources.list /etc/apt/sources.list_backup_ald
cat > /etc/apt/sources.list <<EOF

deb https://dl.astralinux.ru/astra/frozen/1.7_x86-64/1.7.3/repository-base 1.7_x86-64 main non-free contrib
deb https://dl.astralinux.ru/astra/frozen/1.7_x86-64/1.7.3/repository-extended 1.7_x86-64 main contrib non-free
EOF

cat > /etc/apt/sources.list.d/aldpro.list <<EOF

deb https://dl.astralinux.ru/aldpro/stable/repository-main/ 1.4.1 main
deb https://dl.astralinux.ru/aldpro/stable/repository-extended/ generic main
EOF

cat > /etc/apt/preferences.d/aldpro <<EOF

Package: *
Pin: release n=generic
Pin-Priority: 900
EOF


echo ""
echo "обновлем ПО из репов"

apt update &&  apt dist-upgrade -y

#reboot
echo ""

read -sn1 -p "Проверка перед установкой, если все Ок, нажмите любую клавишу, для прерывания нажмите Ctrl+c"; echo


echo "установка ПО для АЛД"
DEBIAN_FRONTEND=noninteractive apt-get install -q -y aldpro-mp

#затем НЕ перезагружаясь правим файл

echo "Правим файл resolv перед настройкой АЛД"

cat > /etc/resolv.conf <<EOF

nameserver 127.0.0.1
search $DOMAIN

EOF

sed -i 's/^dns-nameservers.*/dns-nameservers 127.0.0.1/' /etc/network/interfaces
#после этого рестартуем сеть:

systemctl restart networking

#проверка изменений файла interfaces:
echo ""
echo "проверка изменений файла interfaces:"
echo ""

cat /etc/network/interfaces

#далее ставим командой:
echo ""

read -sn1 -p "Проверка перед установкой, если все Ок, нажмите любую клавишу, для прерывания нажмите Ctrl+c"; echo

echo "установка АЛД pro"

/opt/rbta/aldpro/mp/bin/aldpro-server-install.sh -d $DOMAIN -n $DC_NAME -p $ADMIN_PWD --ip $IP --no-reboot
