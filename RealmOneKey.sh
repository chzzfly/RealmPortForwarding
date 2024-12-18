#!/bin/bash

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo "此脚本需要root权限才能运行，可以使用 'su -' 切换到root用户再运行。"
    exit 1
fi

# 检查realm是否已安装
if [ -f "/root/realm/realm" ]; then
    echo "检测到realm已安装。"
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
else
    echo "realm未安装。"
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
fi

# 检查realm服务状态
check_realm_service_status() {
    if systemctl is-active --quiet realm; then
        echo -e "\033[0;32m启用\033[0m" # 绿色
    else
        echo -e "\033[0;31m未启用\033[0m" # 红色
    fi
}

# 显示菜单的函数
show_menu() {
    clear
    echo "欢迎使用realm一键转发脚本"
    echo "================="
    echo "1. 部署环境"
    echo "2. 添加转发"
    echo "3. 查看已添加的转发规则"
    echo "4. 删除转发"
    echo "5. 启动服务"
    echo "6. 停止服务"
    echo "7. 一键卸载"
    echo "0. 退出脚本"
    echo "================="
    echo -e "realm 状态：${realm_status_color}${realm_status}\033[0m"
    echo -n "realm 转发状态："
    check_realm_service_status
}

# 部署环境的函数
deploy_realm() {
    # 获取最新版本号
    echo "正在获取最新版本信息..."
    latest_version=$(curl -s https://api.github.com/repos/zhboner/realm/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$latest_version" ]; then
        echo "无法获取最新版本信息，请检查网络连接。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo "检测到最新版本：${latest_version}"
    mkdir -p /root/realm
    cd /root/realm
    
    echo "开始下载最新版本..."
    wget -O realm.tar.gz "https://github.com/zhboner/realm/releases/download/${latest_version}/realm-x86_64-unknown-linux-gnu.tar.gz"
    
    if [ $? -ne 0 ]; then
        echo "下载失败，请检查网络连接。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi
    
    echo "解压文件..."
    tar -xvf realm.tar.gz
    chmod +x realm
    rm -f realm.tar.gz  # 清理下载的压缩包
    
    # 创建服务文件
    echo "[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c /root/realm/config.toml

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service
    
    systemctl daemon-reload
    # 更新realm状态变量
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
    echo "部署完成。当前版本：${latest_version}"
    read -n 1 -s -r -p "按任意键继续..."
}

# 卸载realm
uninstall_realm() {
    echo "开始卸载 realm..."
    echo "正在执行以下操作："
    
    echo "1. 停止 realm 服务..."
    systemctl stop realm
    echo "   ✓ 服务已停止"
    
    echo "2. 禁用 realm 服务自启动..."
    systemctl disable realm
    echo "   ✓ 服务自启动已禁用"
    
    echo "3. 删除 realm 服务文件..."
    if [ -f "/etc/systemd/system/realm.service" ]; then
        rm -f /etc/systemd/system/realm.service
        echo "   ✓ 服务文件已删除：/etc/systemd/system/realm.service"
    else
        echo "   - 服务文件不存在，跳过"
    fi
    
    echo "4. 重新加载 systemd..."
    systemctl daemon-reload
    echo "   ✓ systemd 已重新加载"
    
    echo "5. 删除 realm 程序及配置..."
    if [ -d "/root/realm" ]; then
        echo "   - 删除配置文件：/root/realm/config.toml"
        echo "   - 删除主程序：/root/realm/realm"
        rm -rf /root/realm
        echo "   ✓ realm 目录已完全删除"
    else
        echo "   - realm 目录不存在，跳过"
    fi

    # 更新realm状态变量
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
    
    echo "6. 删除本脚本..."
    echo "   即将删除：$0"
    echo "realm 已完全卸载。"
    echo -e "按任意键删除脚本并退出..."
    read -n 1 -s -r
    
    # 创建一个临时脚本来删除本脚本并退出
    local temp_script="/tmp/remove_script.sh"
    echo "#!/bin/bash
sleep 1
rm -f \"$0\"
rm -f \"$temp_script\"" > "$temp_script"
    chmod +x "$temp_script"
    
    # 在后台运行临时脚本并退出
    nohup "$temp_script" >/dev/null 2>&1 &
    exit 0
}

# 删除转发规则的函数
delete_forward() {
    if [ ! -f "/root/realm/config.toml" ]; then
        echo "配置文件不存在。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    # 使用awk一次性读取并处理文件
    local rules=$(awk '/remote =/ {
        gsub(/.*"/, "");
        gsub(/".*/, "");
        print NR ":" $0
    }' /root/realm/config.toml)

    if [ -z "$rules" ]; then
        echo "没有发现任何转发规则。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    echo "当前转发规则："
    local index=1
    while IFS=: read -r line_num target; do
        echo "${index}. ${target}"
        let index+=1
    done <<< "$rules"

    echo "请输入要删除的转发规则序号，直接按回车返回主菜单。"
    read -p "选择: " choice

    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]] || [ $choice -lt 1 ] || [ $choice -gt $((index-1)) ]; then
        echo "无效的选择。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    # 使用awk一次性完成规则块的删除和文件修复
    awk -v target_idx="$choice" '
    BEGIN { 
        count = 0 
        printing = 1
        found_target = 0
    }
    /^\[\[endpoints\]\]/ { 
        if (printing) {
            count++ 
            if (count == target_idx) {
                printing = 0
                found_target = 1
                next
            }
        } else {
            printing = 1
        }
    }
    printing { print }
    END {
        if (!found_target) {
            exit 1
        }
    }' /root/realm/config.toml > /root/realm/config.toml.tmp

    if [ $? -eq 0 ]; then
        mv /root/realm/config.toml.tmp /root/realm/config.toml

        # 检查并确保基本配置存在
        if [ ! -s "/root/realm/config.toml" ] || ! grep -q "^\[network\]$" /root/realm/config.toml; then
            echo -e "[network]\nno_tcp = false\nuse_udp = true\n$(cat /root/realm/config.toml 2>/dev/null)" > /root/realm/config.toml
        fi

        echo "转发规则已删除。"
    else
        rm -f /root/realm/config.toml.tmp
        echo "删除操作失败。"
    fi
    read -n 1 -s -r -p "按任意键继续..."
}

# 添加转发规则
add_forward() {
    # 首先检查 realm 是否已安装
    if [ ! -d "/root/realm" ]; then
        echo "请先安装 realm（选项1）再添加转发规则。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    # 检查配置文件是否存在，如果不存在则创建基础配置
    if [ ! -f "/root/realm/config.toml" ]; then
        # 确保目录存在
        mkdir -p /root/realm
        
        # 创建初始配置文件
        echo "[network]
no_tcp = false
use_udp = true" > /root/realm/config.toml
    fi

    while true; do
        read -p "请输入目的地IP: " ip
        read -p "请输入目的地端口: " port
        
        # 追加新的endpoints配置到config.toml文件
        echo -e "\n[[endpoints]]
listen = \"0.0.0.0:$port\"
remote = \"$ip:$port\"" >> /root/realm/config.toml
        
        read -p "是否继续添加(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            echo "转发规则添加完成。"
            read -n 1 -s -r -p "按任意键继续..."
            break
        fi
    done
}

# 查看转发规则的函数
show_forwards() {
    if [ ! -f "/root/realm/config.toml" ]; then
        echo "配置文件不存在，尚未添加任何转发规则。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    echo "当前所有转发规则："
    echo "=================="
    
    local IFS=$'\n'
    local lines=($(grep 'remote =' /root/realm/config.toml))
    
    if [ ${#lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    local index=1
    for line in "${lines[@]}"; do
        local remote=$(echo $line | cut -d '"' -f 2)
        echo "$index. $remote"
        let index+=1
    done
    echo "=================="
    read -n 1 -s -r -p "按任意键继续..."
}

# 检查并处理权限的函数
check_permission() {
    local cmd=$1
    if [ "$EUID" -eq 0 ]; then
        # root用户直接执行
        $cmd >/dev/null 2>&1
    else
        # 非root用户，检查是否有sudo
        if command -v sudo >/dev/null 2>&1; then
            sudo $cmd >/dev/null 2>&1
        else
            echo "错误：当前用户不是root用户，且未安装sudo。"
            echo "请选择以下方式之一："
            echo "1. 使用root用户运行此脚本"
            echo "2. 安装sudo：apt-get install sudo 或 yum install sudo"
            read -n 1 -s -r -p "按任意键继续..."
            return 1
        fi
    fi
    return 0
}

# 检查配置文件格式的函数
check_config_file() {
    local config_file="/root/realm/config.toml"
    
    # 检查文件是否存在
    if [ ! -f "$config_file" ]; then
        echo "错误：配置文件不存在。"
        return 1
    fi

    # 检查文件是否为空
    if [ ! -s "$config_file" ]; then
        echo "错误：配置文件为空。"
        return 1
    fi

    # 检查基本配置节点
    if ! grep -q "^\[network\]$" "$config_file"; then
        echo "错误：缺少 [network] 配置节点。"
        return 1
    fi

    # 检查是否有endpoints配置
    if ! grep -q "^\[\[endpoints\]\]$" "$config_file"; then
        echo "错误：没有配置任何转发规则。"
        return 1
    fi

    # 检查每个endpoints块是否完整
    local line_num=1
    local in_endpoints=false
    local has_listen=false
    local has_remote=false
    
    while IFS= read -r line || [ -n "$line" ]; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        if [[ "$line" =~ ^\[\[endpoints\]\]$ ]]; then
            # 检查上一个endpoints块是否完整
            if $in_endpoints; then
                if ! $has_listen || ! $has_remote; then
                    echo "错误：第 $line_num 行之前的转发规则配置不完整。"
                    return 1
                fi
            fi
            in_endpoints=true
            has_listen=false
            has_remote=false
        elif [[ "$line" =~ ^listen[[:space:]]*= ]]; then
            has_listen=true
        elif [[ "$line" =~ ^remote[[:space:]]*= ]]; then
            has_remote=true
        fi
        ((line_num++))
    done < "$config_file"

    # 检查最后一个endpoints块
    if $in_endpoints && (! $has_listen || ! $has_remote); then
        echo "错误：最后一个转发规则配置不完整。"
        return 1
    fi

    return 0
}

# 启动服务
start_service() {
    if systemctl is-active --quiet realm; then
        echo "realm服务已经在运行中。"
        sleep 1
        return
    fi

    # 检查配置文件
    if ! check_config_file; then
        echo "启动失败：配置文件存在错误，请检查配置文件（/root/realm/config.toml）。"
        read -n 1 -s -r -p "按任意键继续..."  # 错误情况保留read，让用户确认看到错误信息
        return
    fi

    echo "正在启动realm服务..."
    
    # 首先检查权限
    if ! check_permission "systemctl show-environment" ; then
        return
    fi
    
    # 执行服务操作
    if ! check_permission "systemctl unmask realm.service" ; then
        echo "服务操作失败：无法解除服务屏蔽"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    if ! check_permission "systemctl daemon-reload" ; then
        echo "服务操作失败：无法重载系统服务"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    if ! check_permission "systemctl restart realm.service" ; then
        echo "服务操作失败：无法重启服务"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    if ! check_permission "systemctl enable realm.service" ; then
        echo "服务操作失败：无法设置服务自启动"
        read -n 1 -s -r -p "按任意键继续..."
        return
    fi

    # 给服务一点启动时间
    sleep 1
    if ! systemctl is-active --quiet realm; then
        echo "realm服务启动失败。查看详细错误信息："
        systemctl status realm
        read -n 1 -s -r -p "按任意键继续..."  # 错误情况保留read，让用户确认看到错误信息
        return
    fi

    echo "realm服务已启动并设置为开机自启。"
    sleep 1
}

# 停止服务
stop_service() {
    if ! systemctl is-active --quiet realm; then
        echo "realm服务当前未运行。"
        sleep 1
        return
    fi
    systemctl stop realm
    echo "realm服务已停止。"
    sleep 1
}

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项: " choice
    case $choice in
        1)
            deploy_realm
            ;;
        2)
            add_forward
            ;;
        3)
            show_forwards
            ;;
        4)
            delete_forward
            ;;
        5)
            start_service
            ;;
        6)
            stop_service
            ;;
        7)
            uninstall_realm
            ;;
        0)
            echo "感谢使用，再见！"
            exit 0
            ;;
        *)
            echo "无效选项: $choice"
            ;;
    esac
done
