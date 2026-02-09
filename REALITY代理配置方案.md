# 自动配置方法

> 常见报错解决:
> 1、ssh连接如果报错  WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
>
> 解决方法：先执行`ssh-keygen -R 服务器ip`，再次执行ssh命令

## 1、服务器安全配置

1、服务器中执行

```shell
#安装防火墙、fail2ban
apt update
apt install ufw -y
apt install fail2ban -y

#配置防火墙
ufw default deny incoming
ufw default allow outgoing
ufw allow 22
ufw allow 443

#启动
ufw enable
#检查状态
systemctl status ufw
ufw status
```

2、在Windows上执行

```shell
#jail.local需要替换为该文件在windows上的实际路径
scp jail.local root@服务器ip:/etc/fail2ban/
```

3、服务器中执行

```shell
#重启fail2ban
systemctl restart fail2ban
#设置开机自启动
systemctl enable fail2ban
#检查fail2ban状态
systemctl status fail2ban

#查看 fail2ban拦截历史 命令
fail2ban-client status
fail2ban-client status sshd
iptables -L f2b-sshd -n --line-numbers
```

## 2、代理一键安装脚本使用

1、在Windows CMD（或者powerShell）上执行

```shell
#install_xray_reality.sh需要替换为该文件在windows上的实际路径
scp install_xray_reality.sh root@服务器ip:/tmp
#连接服务器终端(如未连接)
ssh root@服务器ip  
```

2、服务器中执行

```shell
#加x权限
chmod +x /tmp/install_xray_reality.sh
#执行
/tmp/install_xray_reality.sh
```











# 手动配置方法

# REALITY + VLESS + vision代理配置方案 

## 1、GitHub项目地址

- Xray-core：https://github.com/XTLS/Xray-core
- Xray-install：https://github.com/XTLS/Xray-install/tree/main （一键部署）

## 2、服务端配置

### 2.1 前置准备

- 一台Linux 服务器
- 确保端口 **443** 未被占用（REALITY 必须占用 443 或其他常用 HTTPS 端口以达到最佳伪装效果）
- 拥有 Root 权限

### 2.2 安装 Xray-core

直接使用官方提供的安装脚本（自动安装最新版），会自动配置好 `systemd` 服务

```Bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```

已安装文件位置：

```
- /etc/systemd/system/xray.service
- /etc/systemd/system/xray@.service

- /usr/local/bin/xray
- /usr/local/etc/xray/*.json   #Xray 的配置文件,config.json

- /usr/local/share/xray/geoip.dat
- /usr/local/share/xray/geosite.dat

- /var/log/xray/access.log
- /var/log/xray/error.log
```

### 2.3 生成必要的 ID 和 密钥

需要生成一个用户 UUID 和一对公私钥（用于 REALITY 认证）

在终端依次运行：

```bash
# 1. 生成 UUID
xray uuid
# 输出示例: 53e83453-9906-41d4-995a-112233445566 (记下这个)

# 2. 生成 x25519 密钥对
xray x25519
# 输出示例:
# Private key: 4M... (记下这个作为服务端私钥)
# Public key:  7P... (也可能叫Password，记下这个，客户端填这个)
```



### 2.4 编写配置文件

使用编辑器打开配置文件：

```Bash
vim /usr/local/etc/xray/config.json
```

`config.json`文件内容：

```json
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
            "id": "你的UUID", 
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
          "privateKey": "你的x25519私钥", 
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
```

**关键参数解释：**

- **`port`**: 必须是 443。
- **`id`**: 填入步骤 3 生成的 UUID。
- **`flow`**: 必须保留 `xtls-rprx-vision` 以启用 Vision 流控。
- **`dest`**: 你要伪装的目标网站。推荐选择国外的大型网站（支持 TLS 1.3 和 H2），例如 `learn.microsoft.com`，`www.apple.com` 或者 `gateway.icloud.com`。**不要**选 `Google/Youtube`，也不要选被墙的网站。
- **`serverNames`**: 与 `dest` 对应的域名列表，客户端连接时 SNI 必须在此列表中。
- **`privateKey`**: 填入步骤 3 生成的 **私钥**。
- **`shortIds`**: 用于区分客户端的简短 ID，可以是 2 到 16 位的 16 进制字符串，或者留空 `[""]`。

> **`dest`选择测试（可选）：**
>
> ```bash
> #执行以下命令测试，选择延迟最低的
> for d in www.oracle.com www.nvidia.com tag-logger.demandbase.com www.xbox.com assets-www.xbox.com tags.tiqcdn.com api.company-target.com intelcorp.scene7.com digitalassets.tesla.com j.6sc.co learn.microsoft.com www.microsoft.com www.sony.com ; do t1=$(date +%s%3N); timeout 1 openssl s_client -connect $d:443 -servername $d </dev/null &>/dev/null && t2=$(date +%s%3N) && echo "$d: $((t2 - t1)) ms" || echo "$d: timeout"; done
> 
> #www.oracle.com www.nvidia.com www.amd.com tag-logger.demandbase.com www.xbox.com assets-www.xbox.com tags.tiqcdn.com api.company-target.com intelcorp.scene7.com digitalassets.tesla.com j.6sc.co 这部分自己可以增加或减少
> ```

### 2.5 验证并重启服务

保存文件后，测试配置是否合法：

```Bash
xray run -test -c /usr/local/etc/xray/config.json
# 如果输出 "Configuration OK" 则正确
```

重启 Xray 服务并设置开机自启：

```Bash
systemctl restart xray
systemctl enable xray
```

> 其他，防火墙设置：
>
> 如果你开启了 `ufw` 或云服务商的防火墙，务必放行 TCP 443 端口
>
> ```Bash
> # 例如 ufw
> ufw allow 443/tcp
> ```

### 2.6 **网络优化**

开启 BBR 拥塞控制，这对于 Vision 流控的效果至关重要：

```Bash
# 1. 手动加载fq模块
modprobe sch_fq

# 2. 启用 BBR（永久生效）
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# 3. 验证是否生效
sysctl net.ipv4.tcp_congestion_control
# 正确输出应为：net.ipv4.tcp_congestion_control = bbr
```



## 3. 客户端配置（windows）

### 3.1 连接信息

**方法1：**

在客户端（如 `v2rayN`, `Shadowrocket`, `Sing-box` 等）中，添加 VLESS 配置，填入以下信息：

| **参数**               | **值**                                                       |
| ---------------------- | ------------------------------------------------------------ |
| **地址 (Address)**     | 服务器 IP                                                    |
| **端口 (Port)**        | 443                                                          |
| **用户 ID (UUID)**     | xray uuid生成的 UUID                                         |
| **流控 (Flow)**        | `xtls-rprx-vision`                                           |
| **加密 (Encryption)**  | `none`                                                       |
| **传输协议 (Network)** | `tcp`                                                        |
| **伪装类型 (Type)**    | `none`                                                       |
| **传输层安全 (TLS)**   | `reality`                                                    |
| **SNI (ServerName)**   | `learn.microsoft.com` (需与服务端 config 中的 serverNames 一致) |
| **指纹 (Fingerprint)** | `chrome` 或 `firefox`                                        |
| **公钥 (Public Key)**  | **生成的 x25519 公钥** (这是 REALITY 的核心)                 |
| **ShortId**            | `1a` (配置中填的一个)                                        |
| **SpiderX**            | (留空)                                                       |

------

**方法2：**

拼接 `vless://`分享链接。在多个设备上使用，手动拼一个链接发送给自己最方便。格式如下：

```
vless://UUID@服务器IP:443?security=reality&encryption=none&pbk=你的公钥&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=learn.microsoft.com&sid=你的ShortId#你的备注名
```

**替换指南：**

- `UUID`: 换成你的 ID。
- `服务器IP`: 换成 IP。
- `你的公钥`: 换成 `xray x25519` 生成的 **Public Key** (注意经过 URL 编码，通常直接填字符串也没事)。
- `你的ShortId`: 换成配置文件里的值 (例如 `1a`)。
- `learn.microsoft.com`: 如果你改了伪装域名，这里也要改。

拼接好后，复制整段字符，在客户端选择“从剪贴板导入”即可。



## 4. 客户端配置（Android）

### 4.1 安装客户端

- **软件名称**：v2rayNG
- **下载地址 (GitHub)**：https://github.com/2dust/v2rayNG/releases
- **选择文件**：下载 `v2rayNG_1.8.x_universal.apk` (或者更高版本)。

*(备选方案：如果你喜欢更现代的界面，也可以使用 **NekoBox for Android**，配置逻辑是一样的)*

------

### 4.2 配置节点 (两种方法)

**方法 A：通过剪贴板导入 (最快)**

如果之前在电脑上拼接过那个 `vless://` 开头的链接，或者你可以把电脑 v2rayN 里的配置分享出来：

1. **电脑端操作**：
   - 打开电脑上的 v2rayN。
   - 单击选中你的服务器。
   - 按下 `Ctrl + C` (或者右键 -> 导出分享 URL 到剪贴板)。
   - 把这段长长的链接（`vless://.....`）发给手机，并**复制**它
2. **手机端操作**：
   - 打开 v2rayNG。
   - 点击右上角的 **`+`** 号。
   - 选择 **从剪贴板导入**。

------

**方法 B：手动填入**

对着之前的参数表：

1. 打开 v2rayNG，点击右上角 **`+`** 号。
2. 选择 **`输入 VLESS // VLESS (XTLS)`** (手动输入)。
3. **逐行填写 (关键点已加粗)**：

| **字段名**           | **填写内容**            | **备注**                             |
| -------------------- | ----------------------- | ------------------------------------ |
| 别名                 | 随便填 (如: MyServer)   |                                      |
| 地址                 | **你的服务器 IP**       |                                      |
| 端口                 | **443**                 |                                      |
| 用户ID               | 你的 UUID               |                                      |
| **流控 (Flow)**      | **xtls-rprx-vision**    | **必填！** 必须选这个，否则连不上    |
| 传输协议             | **tcp**                 |                                      |
| **伪装类型**         | **none**                | 注意这里选 none                      |
| **传输层安全**       | **reality**             | **核心设置**                         |
| **SNI**              | **learn.microsoft.com** | 必须和windows端一致                  |
| **指纹**             | **chrome**              |                                      |
| **公钥 (PublicKey)** | **你的 x25519 公钥**    | 也就是之前显示为 "Password" 的那一行 |
| **ShortId**          | **1a**                  | 填你设置的短 ID                      |
| SpiderX              | (留空)                  |                                      |

填完后，点击右上角的 **✔️** 保存。

------

### 4.3 测试与连接

1. **选中节点**：确保你刚才添加的配置左边的竖条变成了**绿色**（表示选中）。
2. **测试延迟**：点击右下角的 **V** 图标，或者点击右上角三个点 -> **测试全部配置真连接**。
   - 如果显示 `xxxx ms` (比如 300ms)，说明通了。
   - 如果显示 `-1 ms` 或 `Timeout`，说明配置有错。
3. **启动**：点击右下角的 **V** 图标（连接按钮）。
   - 如果是第一次运行，系统会弹窗“网络连接请求”，点击 **确定/允许**

## 5、服务器安全配置

1、服务器中执行

```shell
#安装防火墙、fail2ban
apt update
apt install ufw -y
apt install fail2ban -y

#配置防火墙
ufw default deny incoming
ufw default allow outgoing
ufw allow 22
ufw allow 443

#启动
ufw enable
#检查状态
systemctl status ufw
ufw status
```

2、在Windows上执行

```shell
#jail.local需要替换为该文件在windows上的实际路径
scp jail.local root@服务器ip:/etc/fail2ban/
```

3、服务器中执行

```shell
#重启fail2ban
systemctl restart fail2ban
#设置开机自启动
systemctl enable fail2ban
#检查fail2ban状态
systemctl status fail2ban

#查看 fail2ban拦截历史 命令
fail2ban-client status
fail2ban-client status sshd
iptables -L f2b-sshd -n --line-numbers
```