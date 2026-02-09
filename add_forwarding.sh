#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="/usr/local/etc/xray/config.json"
BACKUP_FILE="/usr/local/etc/xray/config.json.bak"
TEMP_FILE="/tmp/xray_config_temp.json"
INFO_FILE="/root/xray_reality_info.txt"
XRAY_BIN="/usr/local/bin/xray"

# 1. 检查 Root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用 root 权限运行此脚本。${NC}"
  exit 1
fi

# 2. 检查并安装 jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}检测到未安装 jq，正在安装...${NC}"
    if [ -x "$(command -v apt-get)" ]; then
        apt-get update && apt-get install -y jq
    elif [ -x "$(command -v yum)" ]; then
        yum install -y jq
    else
        echo -e "${RED}无法自动安装 jq，请手动安装 (apt install jq 或 yum install jq)${NC}"
        exit 1
    fi
fi

# 尝试获取旧的公钥
OLD_PUBLIC_KEY=""
if [ -f "$INFO_FILE" ]; then
    OLD_PUBLIC_KEY=$(grep -i "Public Key" "$INFO_FILE" | awk -F: '{print $2}' | tr -d ' ' | head -n 1)
fi

# 捕捉 Ctrl+C 信号
trap "rm -f $TEMP_FILE; echo -e '\n${RED}操作已取消，未修改任何配置。${NC}'; exit 1" SIGINT

echo -e "${CYAN}=== Xray 中转规则配置助手 ===${NC}"

# 3. 备份当前配置
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}当前配置已备份至: $BACKUP_FILE${NC}"
else
    echo -e "${RED}未找到配置文件: $CONFIG_FILE${NC}"
    exit 1
fi

CURRENT_JSON=$(cat "$CONFIG_FILE")

# ==========================================
# 阶段一：架构检查与迁移
# ==========================================
IS_PORTAL=$(echo "$CURRENT_JSON" | jq -r '.inbounds[] | select(.tag == "portal_443") | .tag')

if [ "$IS_PORTAL" != "portal_443" ]; then
    echo -e "${YELLOW}检测到当前为基础架构，正在升级为[端口转发架构]...${NC}"
    EXISTING_SNI=$(echo "$CURRENT_JSON" | jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // "learn.microsoft.com"')
    
    NEW_JSON=$(echo "$CURRENT_JSON" | jq --arg sni "$EXISTING_SNI" '
    .inbounds |= map(
        if .port == 443 then 
            .port = 8443 | .listen = "127.0.0.1" | .tag = "vless_local"
        else . end
    ) |
    .inbounds = ([{
        "port": 443,
        "protocol": "dokodemo-door",
        "tag": "portal_443",
        "settings": { "network": "tcp,udp", "followRedirect": false },
        "sniffing": { "enabled": true, "routeOnly": true, "destOverride": ["tls", "http"] }
    }] + .inbounds) |
    .outbounds += [{
        "protocol": "freedom",
        "tag": "loopback-to-local",
        "settings": { "redirect": "127.0.0.1:8443" }
    }] |
    .routing.rules = ([{
        "type": "field",
        "inboundTag": ["portal_443"],
        "domain": [$sni],
        "outboundTag": "loopback-to-local"
    }] + .routing.rules)
    ')
    
    CURRENT_JSON="$NEW_JSON"
    echo -e "${GREEN}架构升级结构准备就绪${NC}"
else
    echo -e "${GREEN}检测到已是中转架构，准备添加新规则${NC}"
fi

# ==========================================
# 阶段二：交互式收集用户输入 (含重名检测)
# ==========================================

declare -a TAGS
declare -a REDIRECTS
declare -a DOMAINS

INDEX=1

while true; do
    echo -e "\n${YELLOW}>>> 正在配置第 [ $INDEX ] 条规则 ${NC}"
    
    # Tag 输入循环
    while true; do
        read -e -p "请输入转发标签 (tag, 如 relay-hk): " INPUT_TAG
        if [[ -z "$INPUT_TAG" ]]; then echo -e "${RED}输入不能为空。${NC}"; continue; fi
        
        # 检查本次会话重复
        SESSION_DUP=0
        for t in "${TAGS[@]}"; do
            if [[ "$t" == "$INPUT_TAG" ]]; then SESSION_DUP=1; fi
        done
        if [[ $SESSION_DUP -eq 1 ]]; then
            echo -e "${RED}错误：该 Tag [$INPUT_TAG] 在本次操作中已添加过，请使用其他名称。${NC}"
            continue
        fi

        # 检查配置文件重复
        TAG_EXISTS=$(echo "$CURRENT_JSON" | jq -r --arg t "$INPUT_TAG" '.outbounds[] | select(.tag == $t) | .tag')

        if [[ "$TAG_EXISTS" == "$INPUT_TAG" ]]; then
            echo -e "${YELLOW}警告：检测到 Tag [$INPUT_TAG] 已存在于配置文件中！${NC}"
            read -e -p "是否覆盖并修改该配置？(y/n) [n]: " OVERWRITE
            
            if [[ "$OVERWRITE" == "y" || "$OVERWRITE" == "Y" ]]; then
                echo -e "${CYAN}已确认覆盖。旧配置将被删除，替换为新输入的内容。${NC}"
                CURRENT_JSON=$(echo "$CURRENT_JSON" | jq --arg t "$INPUT_TAG" '
                    .outbounds |= map(select(.tag != $t)) |
                    .routing.rules |= map(select(.outboundTag != $t))
                ')
                break 
            else
                echo -e "${YELLOW}请重新输入一个新的 Tag 名称...${NC}"
                continue
            fi
        else
            break
        fi
    done
    
    read -e -p "请输入目标地址 (IP:端口, 如 1.2.3.4:1234): " INPUT_REDIRECT
    if [[ -z "$INPUT_REDIRECT" ]]; then echo -e "${RED}输入不能为空，退出操作。${NC}"; exit 1; fi
    
    read -e -p "请输入匹配域名 (domain, 如 hk.example.com): " INPUT_DOMAIN
    if [[ -z "$INPUT_DOMAIN" ]]; then echo -e "${RED}输入不能为空，退出操作。${NC}"; exit 1; fi
    
    TAGS+=("$INPUT_TAG")
    REDIRECTS+=("$INPUT_REDIRECT")
    DOMAINS+=("$INPUT_DOMAIN")
    
    echo -e "${GREEN}已记录: ${NC} 域名 [${INPUT_DOMAIN}] -> 转发至 [${INPUT_REDIRECT}] (Tag: ${INPUT_TAG})"
    
    read -e -p "是否继续添加下一条? (y/n) [n]: " CONTINUE
    if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
        break
    fi
    ((INDEX++))
done

# ==========================================
# 阶段三：生成最终 JSON
# ==========================================

echo -e "\n${CYAN}正在生成配置文件...${NC}"

FINAL_JSON="$CURRENT_JSON"

for ((i=0; i<${#TAGS[@]}; i++)); do
    TAG="${TAGS[$i]}"
    REDIRECT="${REDIRECTS[$i]}"
    DOMAIN="${DOMAINS[$i]}"
    
    # 注入 outbound
    FINAL_JSON=$(echo "$FINAL_JSON" | jq --arg tag "$TAG" --arg redirect "$REDIRECT" '
        .outbounds += [{
            "protocol": "freedom",
            "tag": $tag,
            "settings": { "redirect": $redirect }
        }]
    ')
    
    # 注入 routing rule
    FINAL_JSON=$(echo "$FINAL_JSON" | jq --arg tag "$TAG" --arg domain "$DOMAIN" '
        .routing.rules = (
            .routing.rules[0:1] + 
            [{
                "type": "field",
                "inboundTag": ["portal_443"],
                "domain": [$domain],
                "outboundTag": $tag
            }] + 
            .routing.rules[1:]
        )
    ')
done

# ==========================================
# 阶段四：验证与应用
# ==========================================

echo "$FINAL_JSON" > "$TEMP_FILE"

echo -e "${CYAN}正在验证配置文件合法性...${NC}"
TEST_OUTPUT=$($XRAY_BIN run -test -c "$TEMP_FILE" 2>&1)

if [[ $TEST_OUTPUT == *"Configuration OK"* ]]; then
    echo -e "${GREEN}配置验证通过！${NC}"
    
    jq . "$TEMP_FILE" > "$CONFIG_FILE"
    
    echo -e "${YELLOW}正在重启 Xray 服务...${NC}"
    systemctl restart xray
    
    if systemctl is-active --quiet xray; then
        echo -e "${GREEN}=== 服务重启成功，配置已生效 ===${NC}"
        
        # ==========================================
        # 阶段五：生成新的 Info 文件
        # ==========================================
        echo -e "${CYAN}正在更新配置详情文件: $INFO_FILE ...${NC}"
        
        VLESS_INFO=$(jq -r '.inbounds[] | select(.protocol=="vless")' "$CONFIG_FILE")
        LOCAL_UUID=$(echo "$VLESS_INFO" | jq -r '.settings.clients[0].id')
        LOCAL_PRIVATE_KEY=$(echo "$VLESS_INFO" | jq -r '.streamSettings.realitySettings.privateKey')
        SNI_LOCAL=$(echo "$VLESS_INFO" | jq -r '.streamSettings.realitySettings.serverNames[0]')
        SHORT_ID=$(echo "$VLESS_INFO" | jq -r '.streamSettings.realitySettings.shortIds[0]')
        
        IPV4_LIST=$(ip -4 addr show | grep global | awk '{print $2}' | cut -d/ -f1)
        IPV6_LIST=$(ip -6 addr show | grep global | awk '{print $2}' | cut -d/ -f1)
        
        # 1. 本机节点信息
        cat > $INFO_FILE <<EOF
====================================================
           Xray 配置详情 (含转发规则)
           更新日期: $(date)
====================================================

[1. 本机直连节点]
----------------------------------------------------
UUID (用户ID):     ${LOCAL_UUID}
公钥 (Public Key): ${OLD_PUBLIC_KEY} 
SNI (域名):        ${SNI_LOCAL}
流控 (Flow):       xtls-rprx-vision
----------------------------------------------------
可用链接:
EOF
        if [[ -n "$IPV4_LIST" ]]; then
            for IP in $IPV4_LIST; do
                LINK="vless://${LOCAL_UUID}@${IP}:443?security=reality&encryption=none&pbk=${OLD_PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_LOCAL}&sid=${SHORT_ID}#Reality_Local_${IP}"
                echo "$LINK" >> $INFO_FILE
                echo "" >> $INFO_FILE
            done
        fi
        if [[ -n "$IPV6_LIST" ]]; then
            for IP in $IPV6_LIST; do
                LINK="vless://${LOCAL_UUID}@[${IP}]:443?security=reality&encryption=none&pbk=${OLD_PUBLIC_KEY}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${SNI_LOCAL}&sid=${SHORT_ID}#Reality_Local_IPv6"
                echo "$LINK" >> $INFO_FILE
                echo "" >> $INFO_FILE
            done
        fi
        
        # 2. 转发节点信息
        cat >> $INFO_FILE <<EOF

====================================================
           [2. 中转/转发 节点配置指南]
====================================================
>>> 只有"SNI"和"地址"需要修改，其他填被转发节点的参数 <<<
----------------------------------------------------
在客户端 (v2rayN/NekoBox) 中添加 VLESS 节点时请按如下填写：

1. 地址 (Address):  填写本机的 IP (见下方可选列表)
2. 端口 (Port):     443
3. SNI (域名):      填写下方表格中对应的 "匹配域名" 
4. UUID (用户ID):   请填写 >>被转发节点<< 的 UUID
5. 公钥 (Public Key):请填写 >>被转发节点<< 的 Public Key
6. 流控 (Flow):     请填写 >>被转发节点<< 的 Flow (通常是 xtls-rprx-vision)

[本机可用 IP 列表]:
EOF
        if [[ -n "$IPV4_LIST" ]]; then
            for IP in $IPV4_LIST; do
                echo "   - ${IP}" >> $INFO_FILE
            done
        fi
        if [[ -n "$IPV6_LIST" ]]; then
            for IP in $IPV6_LIST; do
                echo "   - [${IP}]" >> $INFO_FILE
            done
        fi

        cat >> $INFO_FILE <<EOF

[转发规则对照表]:
目标 Tag         | 匹配域名 (SNI)        | 实际转发去往的目标 (仅供核对)
----------------------------------------------------
EOF
        # 提取并显示规则
        jq -r '
            .outbounds as $obs 
            | .routing.rules[] 
            | select(.inboundTag != null)
            | select(.inboundTag[] | contains("portal_443"))
            | select(.outboundTag != "loopback-to-local" and .outboundTag != "fallback-to-bing")
            | {tag: .outboundTag, domain: .domain[0]} 
            | .tag as $tag 
            | .domain as $domain 
            | ($obs[] | select(.tag == $tag) | .settings.redirect) as $dest 
            | "\($tag) | \($domain) | \($dest)"
        ' "$CONFIG_FILE" | column -t -s "|" >> $INFO_FILE

        echo -e "\n====================================================" >> $INFO_FILE
        echo -e "文件已保存: ${INFO_FILE}" >> $INFO_FILE
        echo -e "${GREEN}配置详情已更新至: ${YELLOW}${INFO_FILE}${NC}"
        echo -e "请运行以下命令查看详细连接信息："
        echo -e "   ${YELLOW}cat ${INFO_FILE}${NC}"

    else
        echo -e "${RED}警告：服务重启失败，正在尝试还原配置...${NC}"
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        systemctl restart xray
        echo -e "${YELLOW}配置已还原至修改前状态。${NC}"
    fi
else
    echo -e "${RED}配置验证失败！${NC}"
    echo "$TEST_OUTPUT"
    echo -e "${YELLOW}原配置未做任何修改。${NC}"
fi

rm -f "$TEMP_FILE"