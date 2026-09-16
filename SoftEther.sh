#!/bin/bash

export LANG=en_US.UTF-8

# 定义颜色变量
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 恢复默认颜色

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    printf "${RED}❌ 请使用 root 权限运行此脚本！(例如: sudo bash vpn.sh)\n${NC}"
    exit 1
fi

# 禁用 bash 历史记录，防止在服务器生成 .bash_history
ln -sf /dev/null ~/.bash_history
history -c

# 检查是否已经安装过
check_installed() {
    if [ -d "/usr/local/vpnserver" ] || [ -f "/etc/systemd/system/vpnserver.service" ]; then
        return 0 # 已安装
    else
        return 1 # 未安装
    fi
}

# 静默卸载（用于清理）
do_uninstall_quiet() {
    if systemctl is-active --quiet vpnserver; then
        systemctl stop vpnserver >/dev/null 2>&1
    fi
    if systemctl is-enabled --quiet vpnserver; then
        systemctl disable vpnserver >/dev/null 2>&1
    fi
    if [ -f "/etc/systemd/system/vpnserver.service" ]; then
        rm -f /etc/systemd/system/vpnserver.service
        systemctl daemon-reload
    fi
    if [ -d "/usr/local/vpnserver" ]; then
        rm -rf /usr/local/vpnserver
    fi
}

# 安装函数
do_install() {
    if check_installed; then
        echo ""
        echo "=================================================="
        printf "${RED}检测到系统中已经安装了 SoftEther VPN Server！\n${NC}"
        printf "${RED}如需重新安装，请先选择选项 2 卸载后再试。\n${NC}"
        echo "=================================================="
        return
    fi

    echo "=== 1. 正在更新软件源并安装编译依赖 ==="
    apt update -y && apt upgrade -y
    apt install -y build-essential gcc g++ make wget curl zlib1g-dev libssl-dev

    echo "=== 2. 正在下载 SoftEther VPN Server (v4.44-9807-rtm) ==="
    DOWNLOAD_URL="https://github.com/SoftEtherVPN/SoftEtherVPN_Stable/releases/download/v4.44-9807-rtm/softether-vpnserver-v4.44-9807-rtm-2025.04.16-linux-x64-64bit.tar.gz"
    wget -qO softether-vpnserver.tar.gz "$DOWNLOAD_URL"

    echo "=== 3. 正在解压文件 ==="
    tar -zxvf softether-vpnserver.tar.gz >/dev/null 2>&1

    echo "=== 4. 正在移动到标准目录 (/usr/local/vpnserver) ==="
    mv vpnserver /usr/local/
    rm -f softether-vpnserver.tar.gz

    echo "=== 5. 正在编译 SoftEther VPN ==="
    cd /usr/local/vpnserver
    # 通过重定向自动同意协议条款（输入 1 三次）
    make <<EOF >/dev/null 2>&1
1
1
1
EOF

    echo "=== 6. 正在设置目录权限 ==="
    chmod 600 /usr/local/vpnserver/*
    chmod 755 /usr/local/vpnserver/vpnserver
    chmod 755 /usr/local/vpnserver/vpncmd

    echo "=== 7. 正在创建 systemd 服务 ==="
    cat <<EOF > /etc/systemd/system/vpnserver.service
[Unit]
Description=SoftEther VPN Server
After=network.target network-online.target

[Service]
Type=forking
ExecStart=/usr/local/vpnserver/vpnserver start
ExecStop=/usr/local/vpnserver/vpnserver stop
Restart=on-failure
WorkingDirectory=/usr/local/vpnserver

[Install]
WantedBy=multi-user.target
EOF

    echo "=== 8. 正在启动并配置开机自启 ==="
    systemctl daemon-reload
    systemctl start vpnserver
    systemctl enable vpnserver >/dev/null 2>&1

    echo ""
    echo "=================================================="
    printf "${GREEN}SoftEther VPN Server v4.44-9807-rtm 安装完成！\n${NC}"
    echo "=================================================="
    printf "${GREEN}提示：请运行以下命令进入管理控制台修改管理员密码：\n${NC}"
    printf "${GREEN}/usr/local/vpnserver/vpncmd\n${NC}"
    echo "=================================================="
}

# 卸载函数
do_uninstall() {
    if ! check_installed; then
        printf "${RED}❌ 系统中未检测到 SoftEther VPN Server，无需卸载。\n${NC}"
        return
    fi

    echo "=== 正在全面清理并卸载 SoftEther VPN Server ==="
    do_uninstall_quiet
    echo "=================================================="
    printf "${GREEN}✅ SoftEther VPN Server 已完全卸载干净！\n${NC}"
    echo "=================================================="
}

# 查看运行状态
check_status() {
    echo "=== 正在检查 SoftEther VPN 运行状态 ==="
    if systemctl is-active --quiet vpnserver; then
        systemctl status vpnserver --no-pager
    else
        printf "${RED}未找到运行中的 vpnserver 服务。\n${NC}"
    fi
}

# 交互主菜单
while true; do
    echo ""
    echo "========================================="
    echo "     SoftEther VPN 服务端一键管理脚本    "
    echo "========================================="
    echo " 1. 安装 SoftEther VPN 服务端"
    echo " 2. 卸载 SoftEther VPN 服务端"
    echo " 3. 查看 VPN 运行状态"
    echo " 0. 退出脚本"
    echo "========================================="
    read -p "请选择操作 [0-3]: " CHOICE

    case "$CHOICE" in
        1)
            do_install
            ;;
        2)
            do_uninstall
            ;;
        3)
            check_status
            ;;
        0)
            echo "退出脚本。"
            exit 0
            ;;
        *)
            printf "${RED}❌ 无效的选项，请输入 0 到 3 之间的数字。\n${NC}"
            ;;
    esac
done
