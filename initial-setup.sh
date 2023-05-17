#!/bin/bash
# ссылка на github https://github.com/NickNeoOne/bash-scripts
# для выполнения запустить команду: curl -fsSL https://raw.githubusercontent.com/NickNeoOne/bash-scripts/main/initial-setup.sh | bash



# установка необходимых пакетов
apt update && apt install -y apt-transport-https lsb-release dialog wget mc nmap traceroute dnsutils ncat telnet mtr-tiny tcpdump htop

# Применение изменений в .bashrc
if grep -q "nickneo" ~/.bashrc; then
    echo "make changes to the file ~/.bashrc"
# Включение возможности перемещаться по истории команд используя частично набранную команду
cat >> ~/.bashrc <<EOF 
# add nickneo alias and settings
if [[ $- == *i* ]]
then
    bind '"\e[A": history-search-backward'
    bind '"\e[B": history-search-forward'
fi
EOF
#
# добавление алиасов
cat >> ~/.bashrc <<EOF 
alias grep-v="grep -Ev '^\s*(;|#|$)'" # Вывод файла без комментариев и пустых строк
alias systemctl-running='systemctl --type=service --state=running' # Список запущенных служб
alias systemctl-failed='systemctl --type=service --state failed' # Список служб со статусом failed
alias systemctl-active='systemctl  --type=service --state=active' # Список активных служб
EOF
source ~/.bashrc
else

    echo "file ~/.bashrc has not been changed because the settings already exist"
    echo "файл ~/.bashrc не был изменен так как настройки уже существуют"
fi
