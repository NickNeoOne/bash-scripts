#!/bin/bash
# ссылка на github https://github.com/NickNeoOne/bash-scripts
# для выполнения запустить команду:
# curl -fsSL https://raw.githubusercontent.com/NickNeoOne/bash-scripts/main/initial-setup.sh -o /tmp/initial-setup.sh ; bash /tmp/initial-setup.sh
# или
# wget --no-cache -qO - https://raw.githubusercontent.com/NickNeoOne/bash-scripts/main/initial-setup.sh -O /tmp/initial-setup.sh ; bash /tmp/initial-setup.sh



CUR_LOCALE=ru_RU.UTF-8

echo "ВВедите имя пользователя/Type your username, please:"
read CUR_USER
echo "You just typed: $CUR_USER"
id $CUR_USER
if [[ $? != 0 ]]; then
echo "Нет, такого пользователя"
exit 1
fi


dpkg -s sudo > /dev/null 2>&1
if [[ $? != 0 ]]; then
echo "Не установлен пакет sudo. Устанoвка"
su -c "apt update && apt install sudo && usermod -a -G sudo $CUR_USER"
su -c "usermod -a -G sudo $CUR_USER"
fi

#echo $CUR_LOCALE

if [[ $LANG != $CUR_LOCALE  ]]; then
echo "Текущая локаль в системе $LANG не совпадает с  заданной переменной пользователем в скрипте: $CUR_LOCALE, запускаем настройку локали"
echo "The current locale in the system $LANG does not match the variable specified by the user in the script: $CUR_LOCALE, starting the locale setup"
#sleep 2
echo "Press any key to continue"

read -s -n 1
sudo dpkg-reconfigure locales
else
echo "Текущая локаль в системе $LANG аналогична заданной переменной пользователем в скрипте: $CUR_LOCALE, Перенастройка локали не требуется"
fi


# установка необходимых пакетов
sudo apt update && sudo apt install -y apt-transport-https lsb-release dialog wget curl mc nmap traceroute dnsutils ncat telnet mtr-tiny tcpdump htop

# Применение изменений в ~/.inputrc
grep -q "$CUR_USER" /home/$CUR_USER/.inputrc
if [[ $? != 0 ]]; then
    echo "make changes to the file /home/$CUR_USER/.inputrc"
# Включение возможности перемещаться по истории команд используя частично набранную команду
cat >> /home/$CUR_USER/.inputrc <<EOF
# add $CUR_USER settings
"\e[A": history-search-backward
"\e[B": history-search-forward
EOF
else
    echo " "
    echo "#######################################################"
    echo "file ~$CUR_USER/.inputrc has not been changed because the settings already exist"
    echo "файл ~$CUR_USER/.inputrc не был изменен так как настройки уже существуют"
fi

grep -q "$CUR_USER" /home/$CUR_USER/.bashrc
if [[ $? != 0 ]]; then
    echo "make changes to the file /home/$CUR_USER/.bashrc"
# добавление алиасов
cat >> /home/$CUR_USER/.bashrc <<EOF
# add $CUR_USER alias
alias grep-v="grep -Ev '^\s*(;|#|$)'" # Вывод файла без комментариев и пустых строк
alias systemctl-running='systemctl --type=service --state=running' # Список запущенных служб
alias systemctl-failed='systemctl --type=service --state failed' # Список служб со статусом failed
alias systemctl-active='systemctl  --type=service --state=active' # Список активных служб
EOF
source /home/$CUR_USER/.bashrc
else
    echo " "
    echo "#######################################################"
    echo "file /home/$CUR_USER/.bashrc has not been changed because the settings already exist"
    echo "фай /home/$CUR_USER/.bashrc не был изменен так как настройки уже существуют"
fi
