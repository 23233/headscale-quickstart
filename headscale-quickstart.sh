#!/bin/bash

cat << "EOF"
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
一键部署headscale
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
EOF

# 在更高版本的docker中 集成了 docker compose
if command -v docker-compose &>/dev/null; then
  DOCKER_COMPOSE_COMMAND="docker-compose"
else
  DOCKER_COMPOSE_COMMAND="docker compose"
fi

# 面板的子站地址
DASHBOARD_SUBDOMAIN="dashboard"
# 对应api的子站地址
API_SUBDOMAIN="api"

check_if_root() {
    if [ $(id -u) -ne 0 ]; then
    echo "该脚本必须以root用户身份运行"
    exit 1
    fi
}

check_dependencies() {
    echo "正在检查依赖项..."

    if ! command -v docker &> /dev/null
    then
        echo "Docker未安装。 尝试安装..."
        if [ -f /etc/debian_version ]; then
            curl -sSL https://get.daocloud.io/docker | sh
        else
            echo "操作系统不支持自动安装Docker"
            exit 1
        fi
    else
        echo "Docker已经安装。"
    fi

    echo "-----------------------------------------------------"
    echo "依赖项检查完成"
    echo "-----------------------------------------------------"

    wait_seconds 3
}

wait_seconds() {(
  for ((a=1; a <= $1; a++))
  do
    echo ". . ."
    sleep 1
  done
)}

confirm() {(
  while true; do
      read -p '是否一切正常 [y/n]: ' yn
      case $yn in
          [Yy]* ) override="true"; break;;
          [Nn]* ) echo "退出..."; exit 1;;
          * ) echo "请回答 yes 或者 no.";;
      esac
  done
)}

pull_config() {
    COMPOSE_URL="https://raw.githubusercontent.com/23233/headscale-quickstart/main/docker-compose.yaml" 
    CADDY_URL="https://raw.githubusercontent.com/23233/headscale-quickstart/main/Caddyfile"
    CONFIG_URL="https://raw.githubusercontent.com/23233/headscale-quickstart/main/config.yaml"
    echo "正在拉取配置文件..."
    mkdir -p ./config
    mkdir -p ./data
    wget -O ./docker-compose.yml $COMPOSE_URL && wget -O ./Caddyfile $CADDY_URL && wget -O ./config/config.yaml $CONFIG_URL
    touch ./config/db.sqlite
}

test_connection() {
    local RETRY_URL=$1
    echo "正在测试Caddy设置(请耐心等待，可能需要1-2分钟)"
    for i in 1 2 3 4 5 6 7 8
    do
    curlresponse=$(curl -vIs $RETRY_URL 2>&1)

    if [[ "$i" == 8 ]]; then
    echo "    Caddy正在设置证书时遇到问题，请检查(docker logs caddy)"
    echo "    退出..."
    exit 1
    elif [[ "$curlresponse" == *"failed to verify the legitimacy of the server"* ]]; then
    echo "    证书尚未配置，正在重试..."

    elif [[ "$curlresponse" == *"left intact"* ]]; then
    echo "    证书配置完成"
    break
    else
    secs=$(($i*5+10))
    echo "    Issue establishing connection...retrying in $secs seconds..."       
    fi
    sleep $secs
    done
}

install() {
    set -e

    CONFIG_DIR="/root/headscale"
    HEADSCALE_BASE_DOMAIN=headscale.$(curl -s ifconfig.me | tr . -).nip.io
    SERVER_PUBLIC_IP=$(curl -s ifconfig.me)

    mkdir -p $CONFIG_DIR
    pushd $CONFIG_DIR

    echo "-----------------------------------------------------"
    echo "您想为headscale使用自己的域名，还是自动生成域名？"
    echo "如果使用自己的域名，请添加泛域名解析（例如：*.headscale.example.com），指向 $SERVER_PUBLIC_IP"
    echo "-----------------------------------------------------"
    select domain_option in "自动生成域名（$HEADSCALE_BASE_DOMAIN）" "自定义域名（例如：headscale.example.com）"; do
        case $REPLY in
            1)
            echo "使用 $HEADSCALE_BASE_DOMAIN 作为基本域名"
            DOMAIN_TYPE="auto"
            break
            ;;
            2)
            read -p "输入自定义域名（确保 *.domain 解析指向 $SERVER_PUBLIC_IP）：" domain
            HEADSCALE_BASE_DOMAIN=$domain
            echo "使用 $HEADSCALE_BASE_DOMAIN"
            DOMAIN_TYPE="custom"
            break
            ;;
            *) echo "无效选项 $REPLY";;
        esac
    done

    wait_seconds 2



    echo "-----------------------------------------------------"
    echo "将使用以下子域名："
    echo "          $DASHBOARD_SUBDOMAIN.$HEADSCALE_BASE_DOMAIN"
    echo "                $API_SUBDOMAIN.$HEADSCALE_BASE_DOMAIN"
    echo "-----------------------------------------------------"

    if [[ "$DOMAIN_TYPE" == "custom" ]]; then
        echo "在继续之前，请确认 DNS 配置正确，记录指向 $SERVER_PUBLIC_IP"
        confirm
    fi

    wait_seconds 1

    unset GET_EMAIL
    unset RAND_EMAIL
    RAND_EMAIL="$(echo $RANDOM | md5sum  | head -c 16)@email.com"
    read -p "输入域名注册邮箱（按 'enter' 使用 $RAND_EMAIL）：" GET_EMAIL
    if [ -z "$GET_EMAIL" ]; then
        echo "使用随机邮箱"
        EMAIL="$RAND_EMAIL"
    else
        EMAIL="$GET_EMAIL"
    fi

    wait_seconds 2

    echo "-----------------------------------------------------------------"
    echo "                安装参数"
    echo "-----------------------------------------------------------------"
    echo "           域名：$HEADSCALE_BASE_DOMAIN"
    echo "           邮箱：$EMAIL"
    echo "      公网IP地址：$SERVER_PUBLIC_IP"
    echo "-----------------------------------------------------------------"
    echo "确认安装设置"
    echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"

    confirm

    echo "-----------------------------------------------------------------"
    echo "开始安装……"
    echo "-----------------------------------------------------------------"

    wait_seconds 3

    pull_config

    echo "设置配置文件……"

    sed -i "s|HEADSCALE_BASE_DOMAIN|${HEADSCALE_BASE_DOMAIN}|g" ./docker-compose.yml
    sed -i "s|HEADSCALE_BASE_DOMAIN|${HEADSCALE_BASE_DOMAIN}|g" ./Caddyfile
    sed -i "s|HEADSCALE_BASE_DOMAIN|${HEADSCALE_BASE_DOMAIN}|g" ./config/config.yaml
    # 替换dashboard
    sed -i "s|DASHBOARD_SUBDOMAIN|${DASHBOARD_SUBDOMAIN}|g" ./Caddyfile
    # 替换api
    sed -i "s|API_SUBDOMAIN|${API_SUBDOMAIN}|g" ./Caddyfile
    sed -i "s|API_SUBDOMAIN|${API_SUBDOMAIN}|g" ./config/config.yaml

    sed -i "s|CONFIG_FOLDER|${CONFIG_DIR}|g" ./config/config.yaml
    sed -i "s|YOUR_EMAIL|${EMAIL}|g" ./Caddyfile

    echo "启动容器..."

    ${DOCKER_COMPOSE_COMMAND} -f ./docker-compose.yml up -d

    sleep 2

    test_connection "https://${API_SUBDOMAIN}.${HEADSCALE_BASE_DOMAIN}"

    wait_seconds 3

    set +e

    echo "-----------------------------------------------------"
    echo "-----------------------------------------------------"
    echo "Headscale设置完成。您现在可以开始使用Headscale。"
    echo "WebUI运行在：https://$DASHBOARD_SUBDOMAIN.$HEADSCALE_BASE_DOMAIN"
    echo "控制器运行在：https://$API_SUBDOMAIN.$HEADSCALE_BASE_DOMAIN"
    echo ""
    echo "要为仪表板生成API密钥，请运行："
    echo "'sudo docker exec headscale headscale apikeys create'"
    echo "并将API密钥复制到仪表板设置中。"
    echo "-----------------------------------------------------"
    echo "-----------------------------------------------------"

    popd
}

check_if_root
check_dependencies
install