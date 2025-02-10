#!/bin/bash
#
# Менеджер контейнеров с Chromium для @NOD3R.
#
# Функционал:
#   1) Установить/Запустить один контейнер (имя контейнера задаётся пользователем,
#      можно задать прокси для каждого контейнера)
#   2) Запустить несколько контейнеров
#   3) Обновить выбранный контейнер
#   4) Удалить выбранный контейнер (с предварительным выводом списка)
#   5) Войти в контейнер (shell)
#   6) Показать список контейнеров
#   7) Обновить скрипт (self-update)
#   8) Выход
#
# Запускайте скрипт с правами root:
#   chmod +x manager.sh
#   ./manager.sh
#

# === Настройка цветов для вывода ===
GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

# === Функция для вывода баннера ===
print_banner() {
  clear
  echo -e "${GREEN}========================================${RESET}"
  echo -e "${GREEN}              N O D 3 R               ${RESET}"
  echo -e "${GREEN}========================================${RESET}"
  echo -e "${GREEN}Подписывайся на NOD3R: https://t.me/nod3r${RESET}"
  echo
}

# === Проверка запуска от root ===
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Пожалуйста, запустите скрипт с правами root.${RESET}"
  exit 1
fi

# Образ Docker, используемый для контейнеров
IMAGE="lscr.io/linuxserver/chromium:latest"

# === Функция: Поиск свободного хостового порта (начиная с 10000) ===
get_free_port() {
  port=10000
  # Используем ss для проверки прослушиваемых портов
  while ss -ltn | awk '{print $4}' | grep -E "(:)$port\$" >/dev/null 2>&1; do
    port=$((port+1))
  done
  echo "$port"
}

# === Функция: Вывод списка контейнеров NOD3R ===
list_containers() {
  echo -e "${GREEN}Список контейнеров NOD3R:${RESET}"
  docker ps -a --filter "name=" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# === Вспомогательная функция: Выбрать контейнер по имени, введённому пользователем ===
choose_container_by_name() {
  local name="$1"
  mapfile -t containers < <(docker ps -a --filter "name=${name}" --format "{{.Names}}")
  if [ ${#containers[@]} -eq 0 ]; then
      echo ""
      return
  elif [ ${#containers[@]} -eq 1 ]; then
      echo "${containers[0]}"
      return
  else
      echo -e "${GREEN}Найдено несколько контейнеров, содержащих '${name}':${RESET}"
      for i in "${!containers[@]}"; do
          echo "$((i+1)). ${containers[$i]}"
      done
      read -p "Введите номер контейнера для выбора: " index
      index=$((index-1))
      if [ $index -ge 0 ] && [ $index -lt ${#containers[@]} ]; then
          echo "${containers[$index]}"
      else
          echo ""
      fi
  fi
}

# === Функция: Установка/Запуск одного контейнера ===
install_container() {
  print_banner
  echo -e "${GREEN}=== Установка/Запуск одного контейнера ===${RESET}"
  read -p "Введите название контейнера (оно же логин для доступа): " CONTAINER_NAME
  read -s -p "Введите пароль: " PASSWORD; echo
  read -s -p "Подтвердите пароль: " PASSWORD_CONFIRM; echo
  if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo -e "${RED}Пароли не совпадают. Отмена установки.${RESET}"
    return
  fi

  # Запрос прокси (если требуется)
  read -p "Введите прокси для контейнера (например, http://user:pass@proxyserver:port) или оставьте пустым: " PROXY
  if [ -n "$PROXY" ]; then
    # Передаём стандартные переменные окружения и CHROMIUM_FLAGS, чтобы Chromium использовал прокси
    PROXY_ENV="-e HTTP_PROXY=$PROXY -e HTTPS_PROXY=$PROXY -e CHROMIUM_FLAGS=--proxy-server=$PROXY"
  else
    PROXY_ENV=""
  fi

  container_name="$CONTAINER_NAME"
  CONFIG_DIR="$HOME/chromium/config_${CONTAINER_NAME}"
  CREDENTIALS_FILE="$HOME/${CONTAINER_NAME}_credentials.json"
  cat <<EOL > "$CREDENTIALS_FILE"
{
  "username": "$CONTAINER_NAME",
  "password": "$PASSWORD"
}
EOL

  echo -e "${GREEN}Загрузка образа Docker с Chromium...${RESET}"
  docker pull "$IMAGE"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Не удалось загрузить образ Docker.${RESET}"
    return
  fi

  mkdir -p "$CONFIG_DIR"
  host_port=$(get_free_port)

  docker run -d --name "$container_name" \
    --privileged \
    -e TITLE=NOD3R \
    -e DISPLAY=:1 \
    -e PUID=1000 \
    -e PGID=1000 \
    -e CUSTOM_USER="$CONTAINER_NAME" \
    -e PASSWORD="$PASSWORD" \
    -e LANGUAGE=en_US.UTF-8 \
    $PROXY_ENV \
    -v "$CONFIG_DIR:/config" \
    -p "${host_port}:3000" \
    --shm-size="2gb" \
    --restart unless-stopped \
    "$IMAGE"
  if [ $? -eq 0 ]; then
    host_ip=$(curl -s ifconfig.me)
    echo -e "${GREEN}Контейнер '$container_name' успешно запущен.${RESET}"
    echo -e "${GREEN}Доступ для '$CONTAINER_NAME': http://${host_ip}:${host_port}/${RESET}"
  else
    echo -e "${RED}Не удалось запустить контейнер.${RESET}"
  fi
}

# === Функция: Запуск нескольких контейнеров ===
install_multiple_containers() {
  print_banner
  echo -e "${GREEN}=== Запуск нескольких контейнеров ===${RESET}"
  read -p "Сколько контейнеров вы хотите запустить? " count
  if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -le 0 ]; then
    echo -e "${RED}Введите корректное число!${RESET}"
    return
  fi

  for ((i=1; i<=count; i++)); do
    echo -e "${GREEN}--- Контейнер $i из $count ---${RESET}"
    read -p "Введите название контейнера (имя пользователя для доступа): " CONTAINER_NAME
    read -s -p "Введите пароль: " PASSWORD; echo
    read -s -p "Подтвердите пароль: " PASSWORD_CONFIRM; echo
    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
      echo -e "${RED}Пароли не совпадают. Пропускаем создание этого контейнера.${RESET}"
      continue
    fi

    read -p "Введите прокси для контейнера (например, http://user:pass@proxyserver:port) или оставьте пустым: " PROXY
    if [ -n "$PROXY" ]; then
      PROXY_ENV="-e HTTP_PROXY=$PROXY -e HTTPS_PROXY=$PROXY -e CHROMIUM_FLAGS=--proxy-server=$PROXY"
    else
      PROXY_ENV=""
    fi

    container_name="$CONTAINER_NAME"
    CONFIG_DIR="$HOME/chromium/config_${CONTAINER_NAME}"
    CREDENTIALS_FILE="$HOME/${CONTAINER_NAME}_credentials.json"
    cat <<EOL > "$CREDENTIALS_FILE"
{
  "username": "$CONTAINER_NAME",
  "password": "$PASSWORD"
}
EOL

    echo -e "${GREEN}Загрузка образа Docker с Chromium...${RESET}"
    docker pull "$IMAGE"
    if [ $? -ne 0 ]; then
      echo -e "${RED}Не удалось загрузить образ Docker.${RESET}"
      continue
    fi

    mkdir -p "$CONFIG_DIR"
    host_port=$(get_free_port)

    docker run -d --name "$container_name" \
      --privileged \
      -e TITLE=NOD3R \
      -e DISPLAY=:1 \
      -e PUID=1000 \
      -e PGID=1000 \
      -e CUSTOM_USER="$CONTAINER_NAME" \
      -e PASSWORD="$PASSWORD" \
      -e LANGUAGE=en_US.UTF-8 \
      $PROXY_ENV \
      -v "$CONFIG_DIR:/config" \
      -p "${host_port}:3000" \
      --shm-size="2gb" \
      --restart unless-stopped \
      "$IMAGE"
    if [ $? -eq 0 ]; then
      host_ip=$(curl -s ifconfig.me)
      echo -e "${GREEN}Контейнер '$container_name' успешно запущен.${RESET}"
      echo -e "${GREEN}Доступ для '$CONTAINER_NAME': http://${host_ip}:${host_port}/${RESET}"
    else
      echo -e "${RED}Не удалось запустить контейнер '$container_name'.${RESET}"
      continue
    fi
  done
}

# === Функция: Обновление контейнера ===
update_container() {
  print_banner
  echo -e "${GREEN}=== Обновление контейнера ===${RESET}"
  read -p "Введите название контейнера для обновления: " NAME_INPUT
  container_name=$(choose_container_by_name "$NAME_INPUT")
  if [ -z "$container_name" ]; then
    echo -e "${RED}Контейнер '$NAME_INPUT' не найден.${RESET}"
    return
  fi
  echo -e "${GREEN}Выбран контейнер: $container_name${RESET}"
  
  host_port=$(docker inspect --format='{{(index (index .NetworkSettings.Ports "3000/tcp") 0).HostPort}}' "$container_name")
  config_dir="$HOME/chromium/config_${container_name}"

  echo -e "${GREEN}Останавливаем контейнер $container_name...${RESET}"
  docker stop "$container_name"
  echo -e "${GREEN}Удаляем контейнер $container_name...${RESET}"
  docker rm "$container_name"

  echo -e "${GREEN}Обновляем образ Docker с Chromium...${RESET}"
  docker pull "$IMAGE"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Не удалось обновить образ Docker.${RESET}"
    return
  fi

  # Запрашиваем новые настройки прокси (если требуются)
  read -p "Введите прокси для контейнера (например, http://user:pass@proxyserver:port) или оставьте пустым: " PROXY
  if [ -n "$PROXY" ]; then
    PROXY_ENV="-e HTTP_PROXY=$PROXY -e HTTPS_PROXY=$PROXY -e CHROMIUM_FLAGS=--proxy-server=$PROXY"
  else
    PROXY_ENV=""
  fi

  CREDENTIALS_FILE="$HOME/${container_name}_credentials.json"
  if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo -e "${RED}Файл с учетными данными не найден. Запустите установку заново.${RESET}"
    return
  fi
  USERNAME_FROM_FILE=$(jq -r '.username' "$CREDENTIALS_FILE")
  PASSWORD=$(jq -r '.password' "$CREDENTIALS_FILE")

  echo -e "${GREEN}Запускаем обновленный контейнер: $container_name на порту ${host_port}${RESET}"
  docker run -d --name "$container_name" \
    --privileged \
    -e TITLE=NOD3R \
    -e DISPLAY=:1 \
    -e PUID=1000 \
    -e PGID=1000 \
    -e CUSTOM_USER="$USERNAME_FROM_FILE" \
    -e PASSWORD="$PASSWORD" \
    -e LANGUAGE=en_US.UTF-8 \
    $PROXY_ENV \
    -v "$config_dir:/config" \
    -p "${host_port}:3000" \
    --shm-size="2gb" \
    --restart unless-stopped \
    "$IMAGE"
  if [ $? -eq 0 ]; then
    host_ip=$(curl -s ifconfig.me)
    echo -e "${GREEN}Контейнер обновлён и запущен.${RESET}"
    echo -e "${GREEN}Доступ: http://${host_ip}:${host_port}/${RESET}"
  else
    echo -e "${RED}Ошибка при запуске обновлённого контейнера.${RESET}"
  fi
}

# === Функция: Удаление контейнера (с выводом списка) ===
remove_container() {
  print_banner
  echo -e "${GREEN}=== Удаление контейнера ===${RESET}"
  list_containers
  read -p "Введите название контейнера для удаления: " NAME_INPUT
  container_name=$(choose_container_by_name "$NAME_INPUT")
  if [ -z "$container_name" ]; then
    echo -e "${RED}Контейнер '$NAME_INPUT' не найден.${RESET}"
    return
  fi
  echo -e "${GREEN}Останавливаем контейнер $container_name...${RESET}"
  docker stop "$container_name"
  echo -e "${GREEN}Удаляем контейнер $container_name...${RESET}"
  docker rm "$container_name"
  echo -e "${GREEN}Контейнер '$container_name' удалён.${RESET}"
}

# === Функция: Вход в контейнер (shell) ===
enter_container() {
  print_banner
  echo -e "${GREEN}=== Вход в контейнер (shell) ===${RESET}"
  read -p "Введите название контейнера для входа: " NAME_INPUT
  container_name=$(choose_container_by_name "$NAME_INPUT")
  if [ -z "$container_name" ]; then
    echo -e "${RED}Контейнер '$NAME_INPUT' не найден или не запущен.${RESET}"
    return
  fi
  echo -e "${GREEN}Входим в контейнер $container_name...${RESET}"
  docker exec -it "$container_name" /bin/bash
}

# === Функция: Обновление скрипта (self-update) ===
update_script() {
  print_banner
  echo -e "${GREEN}=== Обновление скрипта ===${RESET}"
  # Замените URL ниже на актуальный адрес вашего скрипта на GitHub
  SCRIPT_URL="https://raw.githubusercontent.com/k2wGG/multichome-vps/refs/heads/main/install.sh"
  cp "$0" "$0.bak"
  echo -e "${GREEN}Загружаем обновлённую версию скрипта...${RESET}"
  curl -fsSL "$SCRIPT_URL" -o "$0"
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Скрипт успешно обновлён. Перезапустите его.${RESET}"
  else
    echo -e "${RED}Ошибка при обновлении скрипта. Восстанавливаю резервную копию.${RESET}"
    mv "$0.bak" "$0"
  fi
}

# === Главное меню ===
while true; do
  print_banner
  echo -e "${GREEN}Выберите действие:${RESET}"
  echo -e "${GREEN}1) Установить/Запустить один контейнер${RESET}"
  echo -e "${GREEN}2) Запустить несколько контейнеров${RESET}"
  echo -e "${GREEN}3) Обновить контейнер${RESET}"
  echo -e "${GREEN}4) Удалить контейнер${RESET}"
  echo -e "${GREEN}5) Войти в контейнер (shell)${RESET}"
  echo -e "${GREEN}6) Показать список контейнеров${RESET}"
  echo -e "${GREEN}7) Обновить скрипт${RESET}"
  echo -e "${GREEN}8) Выход${RESET}"
  read -p "Введите номер опции: " option

  case $option in
    1) install_container ;;
    2) install_multiple_containers ;;
    3) update_container ;;
    4) remove_container ;;
    5) enter_container ;;
    6) list_containers ;;
    7) update_script ;;
    8) echo -e "${GREEN}Выход...${RESET}"; exit 0 ;;
    *) echo -e "${RED}Неверный выбор. Попробуйте ещё раз.${RESET}" ;;
  esac

  echo -e "${GREEN}Нажмите Enter, чтобы продолжить...${RESET}"
  read
done
