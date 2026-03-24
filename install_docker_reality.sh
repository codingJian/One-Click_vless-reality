#!/bin/bash

# ====================================================
# Xray REALITY (Docker 版) 一键部署脚本
# ====================================================

# 定义颜色，方便查看输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

INSTALL_DIR="/opt/xray-reality"
CONFIG_DIR="${INSTALL_DIR}/config"
LOG_DIR="${INSTALL_DIR}/logs"
INFO_FILE="${INSTALL_DIR}/xray_reality_info.txt"
KEY_FILE="${INSTALL_DIR}/UUID-key.txt"
IMAGE_NAME="ghcr.io/xtls/xray-core:latest"

echo -e "${YELLOW}=== 开始部署 Xray REALITY (Docker 版) ===${NC}"

# 1. 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}请使用 root 权限运行此脚本${NC}"
  exit 1
fi

# 2. 检查并安装 Docker 环境
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}正在安装 Docker...${NC}"
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
fi

# 检查 docker compose 插件
if ! docker compose version &> /dev/null; then
    echo -e "${RED}未检测到 Docker Compose 插件，请检查 Docker 安装状态。${NC}"
    exit 1
fi

# 3. 初始化目录结构
echo -e "${GREEN}初始化目录结构...${NC}"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"
chmod 777 "$LOG_DIR"
cd "$INSTALL_DIR"

# 4. 生成核心凭据并记录
echo -e "${GREEN}正在生成 UUID 和 密钥对...${NC}"
echo "UUID:" > "$KEY_FILE"
UUID=$(docker run --rm $IMAGE_NAME uuid)
echo "$UUID" >> "$KEY_FILE"

echo -e "\n密钥:" >> "$KEY_FILE"
KEYS=$(docker run --rm $IMAGE_NAME x25519)
echo "$KEYS" >> "$KEY_FILE"

# 提取私钥
PRIVATE_KEY=$(echo "$KEYS" | grep -i "PrivateKey" | awk '{print $2}')
if [[ -z "$PRIVATE_KEY" ]]; then
    PRIVATE_KEY=$(echo "$KEYS" | grep -i "Private key" | awk '{print $3}')
fi

# 提取公钥
PUBLIC_KEY=$(echo "$KEYS" | grep -i "Password" | awk '{print $2}')
if [[ -z "$PUBLIC_KEY" ]]; then
    PUBLIC_KEY=$(echo "$KEYS" | grep -i "Public key" | awk '{print $3}')
fi

# 检查密钥是否成功生成
if [[ -z "$PRIVATE_KEY" ]] || [[ -z "$PUBLIC_KEY" ]] || [[ -z "$UUID" ]]; then
    echo -e "${RED}错误：凭据生成或提取失败！${NC}"
    cat "$KEY_FILE"
    exit 1
fi

echo -e "UUID: ${YELLOW}$UUID${NC}"
echo -e "Private Key: ${YELLOW}$PRIVATE_KEY${NC}"
echo -e "Public Key: ${YELLOW}$PUBLIC_KEY${NC}"

# 5. 获取本机 IP 并进行智能分类
echo -e "${GREEN}正在分析网络环境...${NC}"
ALL_IPV4_LIST=$(ip -4 addr show | grep global | awk '{print $2}' | cut -d/ -f1)
IPV6_LIST=$(ip -6 addr show | grep global | awk '{print $2}' | cut -d/ -f1)

PUBLIC_IPV4_LIST=""
PRIVATE_IPV4_LIST=""

# 遍历所有 IPv4 并分类
for IP in $ALL_IPV4_LIST; do
    # 匹配局域网及 Docker 内网网段 (10.x, 127.x, 192.168.x, 172.16-31.x)
    if [[ $IP =~ ^10\. ]] || [[ $IP =~ ^127\. ]] || [[ $IP =~ ^192\.168\. ]] || [[ $IP =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        PRIVATE_IPV4_LIST="$PRIVATE_IPV4_LIST $IP"
    else
        PUBLIC_IPV4_LIST="$PUBLIC_IPV4_LIST $IP"
    fi
done

# 根据是否具备 IPv6 动态调整 outbound 策略
if [[ -n "$IPV6_LIST" ]]; then
    echo -e "${GREEN}检测到 IPv6 地址，启用 UseIPv6 路由策略。${NC}"
    OUTBOUND_FREEDOM='{
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "domainStrategy": "UseIPv6" 
      }   
    }'
else
    echo -e "${YELLOW}未检测到 IPv6 地址，禁用 UseIPv6 路由策略。${NC}"
    OUTBOUND_FREEDOM='{
      "protocol": "freedom",
      "tag": "direct"
    }'
fi

# 6. 编写 Xray 配置文件
echo -e "${GREEN}正在写入配置文件 ${CONFIG_DIR}/config.json ...${NC}"
cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "dns": {
    "servers": [
      "https+local://1.1.1.1/dns-query", 
      "1.1.1.1",
      "8.8.8.8",
      "localhost"
    ]
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "tag": "vless_reality",
      "settings": {
        "clients": [
          {
            "id": "${UUID}", 
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "learn.microsoft.com:443",
          "serverNames": [
            "learn.microsoft.com",
            "www.cisco.com",
            "www.oracle.com",
            "azure.microsoft.com",
            "www.amd.com",
            "www.apple.com"
          ],
          "privateKey": "${PRIVATE_KEY}", 
          "shortIds": ["1a", "2b"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    ${OUTBOUND_FREEDOM},
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private", "geoip:cn"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

# 7. 编写 Docker Compose 编排文件
echo -e "${GREEN}正在写入 docker-compose.yml ...${NC}"
cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
services:
  xray:
    image: ${IMAGE_NAME}
    container_name: xray-reality
    restart: always
    network_mode: "host"
    user: "0:0"
    volumes:
      - ./config:/etc/xray
      - ./logs:/var/log/xray
    environment:
      - TZ=Asia/Shanghai
    command: ["run", "-c", "/etc/xray/config.json"]
EOF

# 8. 启动容器
echo -e "${GREEN}启动 Xray 容器...${NC}"
docker compose up -d

if [ $? -ne 0 ]; then
    echo -e "${RED}容器启动失败，请运行 'docker compose logs -f' 查看错误原因。${NC}"
    exit 1
fi

# 9. 网络优化 BBR
echo -e "${GREEN}配置 BBR 网络优化...${NC}"
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    echo -e "BBR 已开启。"
else
    echo -e "BBR 配置已存在，跳过。"
fi

# 10. 生成并保存客户端连接信息
SHORT_ID="1a"

cat > "$INFO_FILE" <<EOF
====================================================
           Xray REALITY (Docker 版) 节点配置详情
           生成的日期: $(date)
====================================================

[认证信息]
用户 ID (UUID):  ${UUID}
ShortId:         ${SHORT_ID}

[密钥信息] (请妥善保管)
私钥 (Private Key): ${PRIVATE_KEY} 
公钥 (Public Key):  ${PUBLIC_KEY} 

[配置参数]
流控 (Flow):     xtls-rprx-vision
SNI:             learn.microsoft.com
指纹 (Fingerprint): chrome
网络 (Network):  tcp

====================================================================
           [一键连接字符串 (VLESS Links)]
           可以直接复制下方代码到客户端(v2rayN/Shadowrocket)导入
====================================================================
EOF

# --- 循环处理 公网 IPv4 ---
if [[ -n "$PUBLIC_IPV4_LIST" ]]; then
    echo -e "\n--- 公网 IPv4 链接 (推荐) ---" >> "$INFO_FILE"
    for IP in $PUBLIC_IPV4_LIST; do
        LINK="vless://${UUID}@${IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=learn.microsoft.com&sid=${SHORT_ID}#Docker_Reality_IPv4"
        echo "$LINK" >> "$INFO_FILE"
        echo "" >> "$INFO_FILE"
    done
else
    echo -e "\n(未检测到公网 IPv4 地址)" >> "$INFO_FILE"
fi

# --- 循环处理 内网 IPv4 ---
if [[ -n "$PRIVATE_IPV4_LIST" ]]; then
    echo -e "\n--- 内网/局域网 IPv4 链接 (仅供内网穿透/集群互通使用) ---" >> "$INFO_FILE"
    for IP in $PRIVATE_IPV4_LIST; do
        LINK="vless://${UUID}@${IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=learn.microsoft.com&sid=${SHORT_ID}#Docker_Reality_IPv4"
        echo "$LINK" >> "$INFO_FILE"
        echo "" >> "$INFO_FILE"
    done
fi

# --- 循环处理 IPv6 ---
if [[ -n "$IPV6_LIST" ]]; then
    echo -e "\n--- 公网 IPv6 链接 ---" >> "$INFO_FILE"
    for IP in $IPV6_LIST; do
        IP_FORMAT="[${IP}]"
        LINK="vless://${UUID}@${IP_FORMAT}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=learn.microsoft.com&sid=${SHORT_ID}#Docker_Reality_IPv6"
        echo "$LINK" >> "$INFO_FILE"
        echo "" >> "$INFO_FILE"
    done
else
    echo -e "\n(未检测到公网 IPv6 地址)" >> "$INFO_FILE"
fi

echo -e "\n====================================================" >> "$INFO_FILE"

# 11. 结束提示
echo -e "\n${GREEN}=== 部署完成！ ===${NC}"
echo -e "工作目录: ${YELLOW}${INSTALL_DIR}${NC}"
echo -e "核心凭证已保存至: ${YELLOW}${KEY_FILE}${NC}"
echo -e "客户端配置信息已保存至: ${YELLOW}${INFO_FILE}${NC}"
echo -e "\n请运行以下命令查看所有完整分类链接: \n${GREEN}cat ${INFO_FILE}${NC}"