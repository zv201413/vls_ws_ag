#!/bin/bash

# --- 1. 配置与变量 ---
WORK_DIR="/home/zv/vless-all"
UUID="8e6290c1-b97e-40c0-b9a3-7e7ed11ce248"
PORT=8003

# --- 2. 卸载函数 (核心新增) ---
do_uninstall() {
    echo "--- 正在启动卸载程序 ---"
    # 停止所有相关进程
    pkill -f xray
    pkill -f cloudflared
    # 删除工作目录
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
        echo "已清理工作目录: $WORK_DIR"
    fi
    # 清理临时文件
    rm -f /tmp/priv
    echo "--- 卸载完成！所有服务已停止 ---"
    exit 0
}

# --- 3. 参数判断 ---
# 如果执行命令带了 uninstall 参数，则直接跳到卸载逻辑
if [ "$1" = "uninstall" ]; then
    do_uninstall
fi

# --- 4. 安装/更新逻辑 (之前的 79Mbps 极速版) ---
mkdir -p $WORK_DIR
cd $WORK_DIR

# 自动安装依赖
if ! command -v wg >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
    apt-get update && apt-get install -y wireguard-tools curl unzip jq
fi

# 检查并下载 Xray
if [ ! -f "xray" ]; then
    arch=$(uname -m)
    case $arch in
        x86_64) plat="64" ;;
        aarch64) plat="arm64-v8a" ;;
        *) plat="64" ;;
    esac
    curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$plat.zip"
    unzip -o xray.zip && rm xray.zip && chmod +x xray
fi

# --- 5. WARP 注册逻辑 ---
generate_warp_conf() {
    echo "正在自动获取 WARP 账户信息..."
    priv_key=$(./xray x25519 | head -n 1 | cut -d ' ' -f 3)
    pub_key=$(echo "$priv_key" | ./xray x25519 | tail -n 1 | cut -d ' ' -f 3)
    auth=$(curl -sX POST "https://api.cloudflareclient.com/v0a1922/reg" -H "Content-Type: application/json" -d '{"install_id":"","tos":"2020-01-22T00:00:00.000Z","key":"'$pub_key'","fcm_token":""}')
    W_PRIV="$priv_key"
    W_V6=$(echo "$auth" | grep -oE '"v6":"[^"]+"' | cut -d'"' -f4)
    W_ID=$(echo "$auth" | grep -oE '"id":"[^"]+"' | cut -d'"' -f4)
    W_TOKEN=$(echo "$auth" | grep -oE '"token":"[^"]+"' | cut -d'"' -f4)
    W_RES=$(curl -sX GET "https://api.cloudflareclient.com/v0a1922/reg/$W_ID" -H "Authorization: Bearer $W_TOKEN" | grep -oE '"reserved":\[[0-9, ]+\]' | cut -d: -f2)
}

# --- 6. 组装配置 ---
if [ "$warp" = "y" ]; then
    generate_warp_conf
    OUTBOUND_JSON='{ "protocol": "wireguard", "settings": { "secretKey": "'$W_PRIV'", "address": ["172.16.0.2/32", "'$W_V6'/128"], "peers": [{ "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", "endpoint": "engage.cloudflareclient.com:2408" }], "reserved": '$W_RES' } }'
else
    OUTBOUND_JSON='{ "protocol": "freedom", "settings": { "domainStrategy": "UseIP" } }'
fi

# --- 7. 写入并启动 ---
cat << JSON > config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $PORT, "protocol": "vless",
    "settings": { "clients": [{"id": "$UUID"}], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "/ws" } }
  }],
  "outbounds": [$OUTBOUND_JSON]
}
JSON

pkill -f xray
nohup ./xray -c config.json > /dev/null 2>&1 &

# --- 8. 输出链接 ---
# 提取 Argo 域名逻辑
DOMAIN=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' $WORK_DIR/argo.log 2>/dev/null | tail -n 1 | sed 's/https:\/\///')
if [ -n "$DOMAIN" ] && pgrep -f cloudflared >/dev/null; then
    ADDRESS=$DOMAIN; REAL_PORT=443; SEC="tls"
else
    ADDRESS=$(curl -s4m5 icanhazip.com); REAL_PORT=$PORT; SEC="none"
fi

echo -e "\n节点链接："
echo "vless://$UUID@$ADDRESS:$REAL_PORT?encryption=none&security=$SEC&sni=$ADDRESS&type=ws&host=$ADDRESS&path=%2Fws#Argo-VLESS-Final"
