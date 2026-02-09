# One-Click_vless-reality
Linux服务器一键式部署vless-REALITY-vision代理，使用的dest(SNI)是"learn.microsoft.com"，并开启BBR网络优化，自动拼接输出代理链接，可一键复制导入客户端使用。

## 一键部署

以Ubuntu系统为例：

1. **连接服务器**

```shell
ssh root@服务器ip
```

> 常见报错解决:
> 1、ssh连接如果报错  WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
>
> 解决方法：先执行`ssh-keygen -R 服务器ip`，再次执行ssh命令

2. **克隆仓库文件**

```shell
git clone https://github.com/codingJian/One-Click_vless-reality.git
```

3. **赋予权限**

```shell
cd ./One-Click_vless-reality
sudo chmod +x *.sh
```

4. **执行安装（需要root身份执行）**

```shell
sudo ./install_xray_reality.sh 
```

**至此，vless-REALITY-vision代理搭建完成，并启动**



------



## 其他功能

### 添加代理中转服务

如果你有被墙的代理IP（同为REALITY代理）需要中转，那么可以使用本项目中提供的的`add_forwarding.sh`脚本，以交互的形式，帮你添加中转节点。

```bash
sudo ./add_forwarding.sh
#之后会以交互的形式引导如果添加节点
```

> 提示：交互过程中，需要你填入的，必须在被墙节点（被中转节点）的配置文件中，inbounds.streamSettings.realitySettings.serverNames中添加上你所填写的SNI（匹配域名）



## 可选优化配置

### 服务器安全配置

1. 给服务器配置ufw防火墙，fail2ban防护：

```shell
#安装ufw、fail2ban
sudo apt update
sudo apt install ufw -y
sudo apt install fail2ban -y

#配置防火墙
sudo ufw default deny incoming
sudo ufw default allow outgoing
#根据个人按需开放端口，这里以ssh端口22，REALITY代理使用到的443端口为例
sudo ufw allow 22
sudo ufw allow 443

#启动
sudo ufw enable
#检查状态
sudo systemctl status ufw
sudo ufw status
```

配置fail2ban配置文件：

```shell
#这里以直接使用本项目中提供的jail.local配置文件为例(可自行修改)
sudo cp ./jail.local /etc/fail2ban/

#重启fail2ban
sudo systemctl restart fail2ban
#设置开机自启动
sudo systemctl enable fail2ban
#检查fail2ban状态
sudo systemctl status fail2ban

#查看 fail2ban拦截历史 命令
fail2ban-client status
fail2ban-client status sshd
iptables -L f2b-sshd -n --line-numbers
```

