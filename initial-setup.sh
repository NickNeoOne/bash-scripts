#!/bin/bash
# ссылка на github https://github.com/NickNeoOne/bash-scripts
# для выполнения запустить команду: curl -fsSL https://raw.githubusercontent.com/NickNeoOne/bash-scripts/main/initial-setup.sh | bash



# установка необходимых пакетов
apt update && apt install -y apt-transport-https lsb-release dialog wget mc nmap traceroute dnsutils ncat telnet mtr-tiny tcpdump htop

# Применение изменений в ~/.inputrc
grep -q "nickneo" ~/.inputrc
if [[ $? != 0 ]]; then
    echo "make changes to the file ~/.inputrc"
# Включение возможности перемещаться по истории команд используя частично набранную команду
cat >> ~/.inputrc <<EOF
# add nickneo settings
"\e[A": history-search-backward
"\e[B": history-search-forward
EOF
else
    echo "#######################################################"
    echo "file ~/.inputrc has not been changed because the settings already exist"
    echo "файл ~/.inputrc не был изменен так как настройки уже существуют"
fi

grep -q "nickneo" ~/.bashrc
if [[ $? != 0 ]]; then
    echo "make changes to the file ~/.bashrc"
# добавление алиасов
cat >> ~/.bashrc <<EOF
# add nickneo alias
alias grep-v="grep -Ev '^\s*(;|#|$)'" # Вывод файла без комментариев и пустых строк
alias systemctl-running='systemctl --type=service --state=running' # Список запущенных служб
alias systemctl-failed='systemctl --type=service --state failed' # Список служб со статусом failed
alias systemctl-active='systemctl  --type=service --state=active' # Список активных служб
EOF
source ~/.bashrc
else
    echo "#######################################################"
    echo "file ~/.bashrc has not been changed because the settings already exist"
    echo "файл ~/.bashrc не был изменен так как настройки уже существуют"
fi
