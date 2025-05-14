#!/bin/bash
# ссылка на github https://github.com/NickNeoOne/bash-scripts
# для выполнения запустить команду:
# curl -fsSL https://raw.githubusercontent.com/NickNeoOne/bash-scripts/main/initial-setup.sh -o /tmp/initial-setup.sh ; bash /tmp/initial-setup.sh
# или
# wget --no-cache -qO - https://raw.githubusercontent.com/NickNeoOne/bash-scripts/main/initial-setup.sh -O /tmp/initial-setup.sh ; bash /tmp/initial-setup.sh


# Задаем локаль
CUR_LOCALE=ru_RU.UTF-8
# Список пакетов для установки
INSTALL_PKG="apt-transport-https lsb-release dialog wget curl mc nmap 
traceroute dnsutils ncat telnet mtr-tiny tcpdump 
htop"




# Цвета для вывода
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[0;33m'
declare -r BLUE='\033[0;34m'
declare -r NC='\033[0m' # No Color

# Функция для установки sudo
install_sudo() {
    # Определяем пакетный менеджер
    if command -v apt &>/dev/null; then
        su -c "apt update && apt install sudo"
    elif command -v yum &>/dev/null; then
        su -c "yum install -y sudo"
    elif command -v dnf &>/dev/null; then
        su -c "dnf install -y sudo"
    else
        echo "Ошибка: Не удалось определить пакетный менеджер!" >&2
        echo "Установите sudo вручную и повторите попытку." >&2
        exit 1
    fi

    # Проверяем успешность установки
    if ! command -v sudo &>/dev/null; then
        echo "Ошибка: Не удалось установить sudo!" >&2
        exit 1
    fi
}

# Проверяем наличие sudo в системе
if ! command -v sudo &>/dev/null; then
    echo "sudo не установлен в системе."
    
    if [[ $EUID -eq 0 ]]; then
        echo "Пытаемся установить sudo..."
        install_sudo
        echo -e "sudo ${GREEN}успешно${NC} установлен!"
    else
        echo "Для установки sudo войдите как root и запустите скрипт снова." >&2
        exit 1
    fi
fi

echo "Введите имя пользователя/Type your username, please:"
read CUR_USER

if [[ -z "$CUR_USER" ]]; then
    echo -e "${RED}Ошибка: Имя пользователя не может быть пустым!${NC}" >&2
    exit 1
fi
# Дополнительная проверка для системных имен
if [[ ! "$CUR_USER" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]{0,31}$ ]]; then
    echo -e "${RED}Недопустимое имя для системного пользователя!${NC}" >&2
    echo -e "${YELLOW}Можно использовать: латинские буквы, цифры, дефисы и подчеркивания.${NC}" >&2
    echo -e "${YELLOW}Длина: 1-32 символа, начинаться с буквы или цифры.${NC}" >&2
    exit 1
fi


# Проверяем существование пользователя
id "$CUR_USER" &>/dev/null

if [[ $? != 0 ]]; then
    echo "Нет, такого пользователя"
    read -p "Хотите создать пользователя $CUR_USER? [Y/n] " answer
    
    case $answer in
        [Yy]* )
            # Проверка прав администратора
            if [[ $EUID -ne 0 ]]; then
                echo -e "${YELLOW}Ошибка:${NC} Для создания пользователя требуются права ${RED}root${NC}! пробуем запусть команду с sudo" >&2
#                echo "Запустите скрипт снова с sudo: sudo $0" >&2
							if sudo adduser  "$CUR_USER"; then
								echo -e "Пользователь $CUR_USER ${GREEN}успешно${NC} создан!"
							else
								echo -e "${RED}Ошибка${NC} при создании пользователя! ${RED}Недостаточно прав!${NC} Выход." >&2
								exit 1
							fi
			else
				if adduser  "$CUR_USER"; then
					echo -e "Пользователь $CUR_USER ${GREEN}успешно${NC} создан!"
#	                echo "Пароль можно задать командой: sudo passwd $CUR_USER"
				else
					echo -e "${RED}Ошибка${NC} при создании пользователя! Выход." >&2
					exit 1
				fi
            fi
            ;;
        * )
            echo "Создание пользователя отменено. Выход." >&2
            exit 1
            ;;
    esac
else
	echo -e "Пользователь $CUR_USER ${GREEN}существует${NC}. Продолжаем работу..."
fi

# Проверяем пользователя на присутствие в группе sudo
EUGS=`getent group sudo | grep $CUR_USER`

if [[ -z "$EUGS" ]]; then
	echo "Пользователя нет группе sudo" >&2
		read -p "Хотите добавить пользователя $CUR_USER? в группу sudo [Y/n] " answer

	case $answer in
		[Yy]* )
			# Проверка прав администратора
			if [[ $EUID -ne 0 ]]; then
				echo -e "${YELLOW}Ошибка:${NC} Для добавления пользователя в группу требуются права ${RED}root${NC}! пробуем запусть команду с sudo" >&2
				if sudo usermod -a -G sudo "$CUR_USER"; then
					echo -e "Пользователь ${GREEN}успешно${NC} добавлен в группу sudo!"
				else
					echo -e "${RED}Ошибка${NC} при добавлении пользователя группу sudo!"
					exit 1
				fi
			else
				if usermod -a -G sudo "$CUR_USER"; then
					echo -e "Пользователь ${GREEN}успешно${NC} $CUR_USER добавлен в группу sudo!"
				else
					echo -e "${RED}Ошибка${NC} при добавлении пользователя группу sudo!" >&2
					exit 1
				fi
			fi
			;;
		* )
			echo "Добавление пользователя в группу sudo отменено. Продолжаем работу..." >&2
			;;
	esac
fi


# Здесь продолжение вашего скрипта



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
sudo apt update && sudo apt install -y $INSTALL_PKG

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
