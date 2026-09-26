# Домашнее задание к занятию 5. «Практическое применение Docker»

Репозиторий форка с приложением: https://github.com/DaneenaL/shvirtd-example-python

Ниже — как я проходил каждое задание, что сломалось по пути и как я это чинил. Заодно сделал все необязательные пункты со звёздочкой.

## Задача 0. Проверка окружения

Стояла версия Docker Compose plugin, всё завелось без танцев с бубном — `docker --version`, `docker compose version` отработали нормально, отдельный `docker-compose` (через дефис) не найден, что и ожидалось — сейчас используется встроенный плагин `docker compose`, а не старый standalone-бинарник.

![docker version check](screenshots/task0/01-docker-version-check.png)

## Задача 1. Dockerfile + multistage сборка

Сначала попробовал прогнать `main.py` локально в venv, чтобы понять, что вообще делает приложение, прежде чем оборачивать его в Docker. Тут же наступил на грабли:

![venv не создался](screenshots/task1/01-venv-error.png)

`python3 -m venv` не завёлся из-за отсутствующего `ensurepip` — на свежем Ubuntu он не ставится по умолчанию, пришлось доустанавливать `python3-venv` и `python3-pip` отдельно.

Саму MySQL для этого теста поднял через `docker run` (контейнер `mysql-venv-test`) — приложение работало в venv без Docker, а база всё равно бралась из контейнера, как и просило задание. После тестов контейнер убрал.

Дальше разбирался с логикой самого приложения и параллельно делал необязательный пункт — вынес имя таблицы в переменную окружения `TABLE_NAME`, чтобы её можно было менять не трогая код. Здесь отдельно оговорюсь: задание просит не менять файлы форка, кроме 5 добавляемых, но сам же необязательный пункт требует править `main.py` (иначе управление именем таблицы через ENV просто негде реализовать) — трогал `main.py` осознанно и только ради этого пункта, больше нигде логику приложения не менял. Долез до багов в своих же правках:

- Сначала забыл поставить `f` перед строкой с `INSERT INTO {table_name}` — в базу пыталась улететь строка с буквальными фигурными скобками:

![500 ошибка](screenshots/task1/02-uvicorn-500-error.png)

- Потом полез проверять `curl`, но случайно стучался не в тот порт (5000 вместо правильного через прокси) — получил не ту ошибку, на которую рассчитывал:

![не тот порт](screenshots/task1/03-wrong-port-curl.png)

- Дальше добавил `f` к SELECT-запросам, но забыл заменить внутри самого текста запроса `requests` на `{table_name}` — по `grep` это стало видно сразу:

![grep находит requests](screenshots/task1/04-table-name-grep-old.png)

Поправил, перепроверил — чисто:

![grep чисто](screenshots/task1/05-table-name-grep-fixed.png)

Вот кусок кода уже в исправленном виде:

![f-string bugfix](screenshots/task1/06-fstring-bug-code.png)

Ещё раз перепутал порт при проверке (уже по привычке тыкал 5000):

![снова не туда](screenshots/task1/07-wrong-port-curl-2.png)

В итоге всё завелось, приложение стабильно отвечает 200 OK и переживает `--reload` без падений:

![работает](screenshots/task1/08-app-working-200ok.png)

Прибрался за собой — деактивировал venv, убрал тестовый контейнер mysql:

![уборка](screenshots/task1/09-cleanup-deactivate.png)

По условию нужно было добавить в форк ровно 5 файлов: `Dockerfile.python`, `compose.yaml`, `.gitignore`, `.dockerignore` и bash-скрипт для деплоя. Собрал и запушил их все — вот коммит с `.gitignore` и `deploy.sh` (сам bash-скрипт для Task 4 держу здесь же, в репозитории, а не только на сервере):

![gitignore + deploy.sh запушены](screenshots/task1/10-gitignore-deploy-push.png)

Дальше написал сам multistage `Dockerfile.python`:

```dockerfile
# ---- Стадия 1: сборка зависимостей ----
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip wheel --no-cache-dir --wheel-dir /app/wheels -r requirements.txt

# ---- Стадия 2: финальный рабочий образ ----
FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /app/wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "5000"]
```

Смысл в том, что в финальный образ попадают только собранные wheel-пакеты, а не весь кэш pip и инструменты сборки — образ получается заметно легче.

## Задача 2 (*). Yandex Container Registry + скан уязвимостей

Создал registry и залогинился через `yc iam create-token`:

![registry + login](screenshots/task2/01-registry-create-login.png)

Собрал образ по своему Dockerfile.python и запушил:

![build + push](screenshots/task2/02-docker-build-push.png)

Встроенный скан уязвимостей в консоли отработал — полный отчёт (CVE, severity, пакет, версия с фиксом) лежит в [`screenshots/task2/03-vulnerabilities.csv`](screenshots/task2/03-vulnerabilities.csv).

## Задача 3. Полный стек через docker compose

Написал `compose.yaml`, который через `include` подключает готовый `proxy.yaml` (haproxy + nginx), не трогая сам файл:

```yaml
include:
  - proxy.yaml

services:
  web:
    build:
      context: .
      dockerfile: Dockerfile.python
    networks:
      backend:
        ipv4_address: 172.20.0.5
    restart: always
    environment:
      DB_HOST: db
      DB_USER: ${MYSQL_USER}
      DB_PASSWORD: ${MYSQL_PASSWORD}
      DB_NAME: ${MYSQL_DATABASE}
    depends_on:
      - db

  db:
    image: mysql:8
    networks:
      backend:
        ipv4_address: 172.20.0.10
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
```

Запустил:

![docker compose up](screenshots/task3/01-compose-up-first-run.png)

Проверка по цепочке nginx → haproxy → fastapi → mysql через порт 8090:

![curl 8090](screenshots/task3/02-curl-check.png)

И убедился, что запросы реально пишутся в базу:

![select from requests](screenshots/task3/03-mysql-select.png)

## Задача 4. Деплой на реальную VM в Yandex Cloud

Создал VM с нуля (Ubuntu 24.04, публичный IP):

![vm created](screenshots/task4/01-vm-created.png)

Подключился по SSH:

![ssh connect](screenshots/task4/02-ssh-connect.png)

Дальше пошли проблемы одна за другой, распишу как было на самом деле, а не причёсанно.

**Проблема 1: битый GPG-ключ Docker.** При добавлении официального репозитория Docker случайно отменил перезапись существующего файла ключа — получил пустой/битый keyring:

![apt update](screenshots/task4/03-apt-update.png)
![gpg issue](screenshots/task4/04-gpg-key-issue.png)

**Проблема 2: download.docker.com не открывается вообще.** Пересоздал ключ правильно, но `apt install` просто завис на 0%:

![висит на нуле](screenshots/task4/05-hang-0percent.png)

Через несколько минут стало ясно — соединение не устанавливается:

![network unreachable](screenshots/task4/06-network-unreachable.png)

Первым делом проверил security group — думал, дело в файрволе:

![security group](screenshots/task4/07-security-group.png)

Но исходящий трафик был открыт полностью. Проверил `curl -v` — и по IPv6, и по IPv4 подключение к `download.docker.com` просто не проходит (timeout):

![curl verbose ipv6](screenshots/task4/08-curl-verbose-ipv6.png)
![curl verbose ipv4 timeout](screenshots/task4/09-curl-verbose-ipv4-timeout.png)

Оказалось, дело не в моей настройке сети — инфраструктура Docker блокирует/обрывает соединения с IP-адресов российских дата-центров (у VM в Yandex Cloud региональный IP из РФ, независимо от того, откуда я сам подключаюсь). Обошёл проблему, установив Docker не из официального репозитория, а из штатных репозиториев Ubuntu (`docker.io` + `docker-compose-v2`):

![docker установлен через workaround](screenshots/task4/10-docker-installed-workaround.png)
![docker version ok](screenshots/task4/11-docker-version-ok.png)

Дальше написал `deploy.sh`, который клонирует форк в `/opt` и поднимает проект:

```bash
#!/bin/bash
set -e

REPO_URL="https://github.com/DaneenaL/shvirtd-example-python.git"
TARGET_DIR="/opt/shvirtd-example-python"

if [ -d "$TARGET_DIR" ]; then
    echo "Репозиторий уже существует, обновляю..."
    cd "$TARGET_DIR"
    sudo git pull
else
    echo "Клонирую репозиторий в $TARGET_DIR..."
    sudo git clone "$REPO_URL" "$TARGET_DIR"
    cd "$TARGET_DIR"
fi

echo "Запускаю docker compose..."
sudo docker compose up -d --build

echo "Готово. Статус контейнеров:"
sudo docker compose ps
```

Первый запуск клонирования почему-то завис на минуту без вывода:

![clone hung](screenshots/task4/12-git-clone-slow.png)

Повторный запуск с `-v` прошёл штатно:

![clone verbose ok](screenshots/task4/13-git-clone-verbose-ok.png)

**Проблема 3: забыл закоммитить свои файлы.** Проверил содержимое на сервере — `Dockerfile.python` и `compose.yaml` не приехали вообще:

![missing files](screenshots/task4/14-missing-files-ls.png)

Оказалось, я их так и не закоммитил у себя локально:

![git status untracked](screenshots/task4/15-git-status-untracked-local.png)

Добавил, закоммитил, запушил — и подтянул на сервере:

![git pull on server](screenshots/task4/16-git-pull-on-server.png)

**Проблема 4: Docker Hub тоже недоступен.** При первом `docker compose up --build` не смогли скачаться `nginx`/`haproxy`/`mysql` — та же история с блокировкой, только теперь для Docker Hub:

![docker hub blocked](screenshots/task4/17-compose-up-dockerhub-blocked.png)

Решил настройкой registry mirror в `/etc/docker/daemon.json` (`mirror.gcr.io`), после чего всё собралось и завелось:

![compose success with mirror](screenshots/task4/18-compose-up-success-mirror.png)

Проверка изнутри сервера и снаружи:

![curl local server](screenshots/task4/19-curl-server-local.png)
![curl external](screenshots/task4/20-curl-external.png)

Внешняя проверка через check-host.net — сначала прогнал через TCP-режим (сервер отвечает из нескольких стран: Кипр, Москва, Санкт-Петербург, Стамбул, Киев; таймауты из дальних точек вроде Австралии и Германии — это особенность маршрутизации до российских дата-центров, а не проблема настройки):

![check-host tcp](screenshots/task4/21-check-host.png)

Но задание просило именно **HTTP**-проверку (check-host.net/check-http), а не просто TCP — она честнее показывает, что за портом реально стоит рабочее приложение, а не просто открытый сокет. Перепроверил через правильный режим — везде код **200 (OK)**:

![check-host http 200](screenshots/task4/23-check-http-200ok.png)

Проверка базы на сервере:

![mysql check on server](screenshots/task4/22-mysql-verify-server.png)

### Задача 4 (*) — remote SSH context

Настроил Docker context для удалённого управления сервером прямо со своей локальной машины через SSH, без захода по ssh вручную:

```bash
docker context create yandex-vm --docker "host=ssh://daneenal@93.77.177.252"
docker context ls
docker context use yandex-vm
docker ps -a
```

`docker ps -a` в контексте `yandex-vm` показывает реальные контейнеры сервера (`db`, `web`, `ingress-proxy`, `reverse-proxy`), хотя команда выполняется локально:

![remote context docker ps](screenshots/task4/24-remote-context-docker-ps.png)

## Задача 5 (*). Автоматические бэкапы MySQL

Задумка простая: контейнер `schnitzler/mysqldump` в сети `backend`, результат — в `/opt/backup`, расписание — через cron хоста, пароль нигде не должен светиться в git.

Первая попытка пошла не по плану — образ по умолчанию поднимается не как разовый дамп, а как постоянно работающий демон со своим внутренним cron:

![pull and hang](screenshots/task5/01-image-pull-and-hang.png)
![crond daemon](screenshots/task5/02-crond-daemon-issue.png)

Остановил лишний контейнер:

![stop and remove](screenshots/task5/03-stop-remove-container.png)

Разобрался, что у образа есть режим одноразового дампа через `--entrypoint ""` с прямым вызовом `mysqldump`. Но тут вылезла ещё одна проблема — устаревший клиент внутри образа не поддерживает `caching_sha2_password`, который MySQL 8 использует по умолчанию:

![caching_sha2 error](screenshots/task5/04-caching-sha2-error.png)

Попробовал переключить root на `mysql_native_password` — а этот плагин в свежих версиях `mysql:8` вообще выключен по умолчанию:

![plugin not loaded](screenshots/task5/05-alter-user-plugin-not-loaded.png)

Заодно словил "permission denied" при редактировании файла без sudo (репозиторий клонирован от root):

![permission denied nano](screenshots/task5/06-permission-denied-nano.png)

Включил плагин флагом `--mysql-native-password=ON` в `compose.yaml` для сервиса `db`, пересоздал контейнер базы, переключил пользователя root на `mysql_native_password`:

![force recreate ok](screenshots/task5/07-force-recreate-alter-user-ok.png)

Финальный скрипт бэкапа (лежит **вне** git-репозитория проекта, в `/opt/backup-mysql.sh`, чтобы пароль в принципе не мог попасть в git — он читается из `.env` в момент запуска, а не хранится в самом скрипте):

```bash
#!/bin/bash
set -e

ENV_FILE="/opt/shvirtd-example-python/.env"
BACKUP_DIR="/opt/backup"
NETWORK="shvirtd-example-python_backend"

mkdir -p "$BACKUP_DIR"

# Подтягиваем пароли из .env в переменные окружения,
# чтобы нигде не хранить их в самом скрипте
set -a
source "$ENV_FILE"
set +a

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

docker run --rm \
  --network "$NETWORK" \
  --entrypoint "" \
  -v "$BACKUP_DIR":/backup \
  schnitzler/mysqldump \
  mysqldump --opt -h db -u root -p"$MYSQL_ROOT_PASSWORD" \
  --result-file="/backup/virtd_${TIMESTAMP}.sql" "$MYSQL_DATABASE"
```

Ручной прогон — дамп получился настоящий, со структурой таблицы и данными:

![manual backup success](screenshots/task5/08-manual-backup-success.png)

Крон-задача (раз в минуту):

```
* * * * * /opt/backup-mysql.sh >> /var/log/mysql-backup.log 2>&1
```

![crontab setup](screenshots/task5/09-crontab-setup.png)

Через пару минут в `/opt/backup` уже несколько свежих файлов с разным timestamp:

![несколько бэкапов](screenshots/task5/10-multiple-backups.png)

## Задача 6. Terraform-бинарник из образа через dive

Скачал образ:

```bash
docker pull hashicorp/terraform:latest
```

`dive` не было — поставил из GitHub releases (deb-пакет):

![pull + dive missing](screenshots/task6/01-pull-image-dive-missing.png)
![dive installed](screenshots/task6/02-dive-installed.png)

В `dive` нашёл слой `COPY dist/linux/amd64/terraform /bin/terraform` и сам файл `terraform` в дереве:

![dive tui](screenshots/task6/03-dive-tui.png)

Дальше — без запуска контейнера, только `docker save` + распаковка нужного слоя. Образ оказался в OCI-формате (blobs по sha256, а не классические layer.tar):

![docker save + extract](screenshots/task6/04-docker-save-extract.png)

Слой не gzip-сжат, первая попытка распаковать с `-z` не прошла:

![tar gzip error](screenshots/task6/05-tar-gzip-error.png)

Нашёл точное имя blob-файла по дайджесту из dive:

![blobs list](screenshots/task6/06-blobs-list.png)
![digest found](screenshots/task6/07-digest-found.png)

Распаковал обычным `tar -xf` (без `-z`) — бинарник нашёлся:

![terraform extracted](screenshots/task6/08-terraform-extracted.png)

Проверил, что он рабочий:

![terraform version](screenshots/task6/09-terraform-version.png)

```
Terraform v1.16.4
on linux_amd64
```

## Итого

Все задачи 0-6 сделаны, включая оба задания со звёздочкой (2 и 5). Основная часть времени ушла не на само приложение, а на то, что VM в Yandex Cloud — это фактически российский IP, из-за чего и Docker Hub, и `download.docker.com` оказались недоступны напрямую. Решалось через установку Docker из репозиториев Ubuntu и через registry mirror (`mirror.gcr.io`) для Docker Hub — рабочий и, кажется, довольно типичный обходной путь для такой ситуации.
