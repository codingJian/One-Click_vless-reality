#!/bin/bash

# 定义颜色，方便查看输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 定义 Xray 程序绝对路径
XRAY_BIN="/usr/local/bin/xray"

echo -e "${YELLOW}=== 开始部署 Xray REALITY 方案 ===${NC}"

# 1. 检查是否为 Root 用户
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}请使用 root 权限运行此脚本 (sudo ./install_reality.sh)${NC}"
  exit 1
fi

# 2. 安装 Xray-core
echo -e "${GREEN}正在安装 Xray-core...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

if [ $? -ne 0 ]; then
    echo -e "${RED}Xray 安装失败，请检查网络连接。${NC}"
    exit 1
fi

sleep 1

# 3. 生成 UUID 和 密钥
echo -e "${GREEN}正在生成 UUID 和 密钥...${NC}"

# 使用绝对路径生成 UUID
UUID=$($XRAY_BIN uuid)
echo -e "UUID: ${YELLOW}$UUID${NC}"

# 使用绝对路径生成 x25519 密钥对
KEYS=$($XRAY_BIN x25519)

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
if [[ -z "$PRIVATE_KEY" ]] || [[ -z "$PUBLIC_KEY" ]]; then
    echo -e "${RED}错误：密钥生成失败！变量为空。${NC}"
    echo -e "调试信息 - 原始输出:\n$KEYS"
    exit 1
fi

echo -e "Private Key: ${YELLOW}$PRIVATE_KEY${NC}"
echo -e "Public Key: ${YELLOW}$PUBLIC_KEY${NC}"

# 4. 编写配置文件
echo -e "${GREEN}正在写入配置文件 /usr/local/etc/xray/config.json ...${NC}"

cat > /usr/local/etc/xray/config.json <<EOF
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
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "domainStrategy": "UseIPv6" 
      }   
    },
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

# 5. 验证并重启服务
echo -e "${GREEN}验证配置并重启服务...${NC}"
TEST_RESULT=$($XRAY_BIN run -test -c /usr/local/etc/xray/config.json 2>&1)

if [[ $TEST_RESULT == *"Configuration OK"* ]]; then
    echo -e "配置验证: ${GREEN}通过${NC}"
    systemctl restart xray
    systemctl enable xray
else
    echo -e "配置验证: ${RED}失败${NC}"
    echo "$TEST_RESULT"
    exit 1
fi

# 6. 网络优化 BBR
echo -e "${GREEN}配置 BBR 网络优化...${NC}"
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    echo -e "BBR 已开启。"
else
    echo -e "BBR 配置已存在，跳过。"
fi

# 7. 获取所有本机 IP 并生成链接
# -------------------------------------------------------------
# 获取所有 IPv4 (排除 127.0.0.1)
IPV4_LIST=$(ip -4 addr show | grep global | awk '{print $2}' | cut -d/ -f1)

# 获取所有 IPv6 (排除 fe80 开头的链路本地地址)
IPV6_LIST=$(ip -6 addr show | grep global | awk '{print $2}' | cut -d/ -f1)

# 8. 生成并保存信息到本地文件
INFO_FILE="/root/xray_reality_info.txt"
SHORT_ID="1a"

# 先写入文件的头部基础信息
cat > $INFO_FILE <<EOF
====================================================
           Xray REALITY 多 IP 配置详情
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
           你可以直接复制下面这行代码到客户端(v2rayN)导入：
====================================================================
EOF

# --- 循环处理 IPv4 ---
if [[ -n "$IPV4_LIST" ]]; then
    echo -e "\n--- IPv4 链接 ---" >> $INFO_FILE
    for IP in $IPV4_LIST; do
        LINK="vless://${UUID}@${IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=learn.microsoft.com&sid=${SHORT_ID}#CloudCone_Server_IPv4"
        echo "$LINK" >> $INFO_FILE
        echo "" >> $INFO_FILE
    done
else
    echo -e "\n(未检测到公网 IPv4 地址)" >> $INFO_FILE
fi

# --- 循环处理 IPv6 ---
if [[ -n "$IPV6_LIST" ]]; then
    echo -e "\n--- IPv6 链接 ---" >> $INFO_FILE
    for IP in $IPV6_LIST; do
        IP_FORMAT="[${IP}]"
        LINK="vless://${UUID}@${IP_FORMAT}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=learn.microsoft.com&sid=${SHORT_ID}#CloudCone_Server_IPv6"
        echo "$LINK" >> $INFO_FILE
        echo "" >> $INFO_FILE
    done
else
    echo -e "\n(未检测到公网 IPv6 地址)" >> $INFO_FILE
fi

echo -e "\n====================================================" >> $INFO_FILE
echo -e "此文件已保存为: ${INFO_FILE}" >> $INFO_FILE

# 9. 结束
echo -e "${GREEN}=== 部署完成！ ===${NC}"
echo -e "配置详情已保存到文件: ${YELLOW}${INFO_FILE}${NC}"
echo -e "请运行以下命令查看详细连接信息："
echo -e "${YELLOW}cat ${INFO_FILE}${NC}"