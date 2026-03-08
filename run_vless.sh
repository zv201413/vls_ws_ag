#!/bin/bash

# --- 1. 环境准备与依赖安装 ---
WORK_DIR="/home/zv/vless-all"
mkdir -p $WORK_DIR
cd $WORK_DIR

# 自动安装必要工具
if ! command -v wg >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
    apt-get update && apt-get install -y wireguard-tools curl unzip jq
fi

# 检查并下载 Xray (如果本地没有)
if [ ! -f "xray" ]; then
    echo "正在下载 Xray 核心文件..."
    arch=$(uname -m)
    case $arch in
        x86_64) plat="64" ;;
        aarch64) plat="arm64-v8a" ;;
        *) plat="64" ;;
    esac
    curl -L -o xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$plat.zip"
    unzip -o xray.zip && rm xray.zip && chmod +x xray
fi

# --- 2. 配置参数 ---
CONFIG_FILE="$WORK_DIR/config.json"
UUID="8e6290c1-b97e-40c0-b9a3-7e7ed11ce248"
PORT=8003

# --- 3. WARP 自动化逻辑 (甬哥同款) ---
generate_warp_conf() {
    echo "正在自动获取 WARP 账户信息..."
    priv_key=$(./xray x25519 | head -n 1 | cut -d ' ' -f 3) # 使用 xray 自带工具生成密钥
    pub_key=$(echo "$priv_key" | ./xray x25519 | tail -n 1 | cut -d ' ' -f 3)
    
    auth=$(curl -sX POST "https://api.cloudflareclient.com/v0a1922/reg" -H "Content-Type: application/json" -d '{"install_id":"","tos":"2020-01-22T00:00:00.000Z","key":"'$pub_key'","fcm_token":""}')
    
    W_PRIV="$priv_key"
    W_V6=$(echo "$auth" | grep -oE '"v6":"[^"]+"' | cut -d'"' -f4)
    W_ID=$(echo "$auth" | grep -oE '"id":"[^"]+"' | cut -d'"' -f4)
    W_TOKEN=$(echo "$auth" | grep -oE '"token":"[^"]+"' | cut -d'"' -f4)
    W_RES=$(curl -sX GET "https://api.cloudflareclient.com/v0a1922/reg/$W_ID" -H "Authorization: Bearer $W_TOKEN" | grep -oE '"reserved":\[[0-9, ]+\]' | cut -d: -f2)
}

# --- 4. 组装 Outbound ---
if [ "$warp" = "y" ]; then
    generate_warp_conf
    OUTBOUND_JSON='{
      "protocol": "wireguard",
      "settings": {
        "secretKey": "'$W_PRIV'",
        "address": ["172.16.0.2/32", "'$W_V6'/128"],
        "peers": [{
          "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "endpoint": "engage.cloudflareclient.com:2408"
        }],
        "reserved": '$W_RES'
      }
    }'
else
    OUTBOUND_JSON='{ "protocol": "freedom", "settings": { "domainStrategy": "UseIP" } }'
fi

# --- 5. 写入配置并启动 ---
cat << JSON > $CONFIG_FILE
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
nohup ./xray -c $CONFIG_FILE > /dev/null 2>&1 &

# --- 6. 生成链接 ---
if pgrep -f cloudflared >/dev/null; then
    # 尝试从日志中动态抓取 trycloudflare 域名
    DOMAIN=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' $WORK_DIR/argo.log 2>/dev/null | tail -n 1 | sed 's/https:\/\///')
    [ -z "$DOMAIN" ] && ADDRESS=$(curl -s4m5 icanhazip.com) || ADDRESS=$DOMAIN
    REAL_PORT=443
    SEC="tls"
else
    ADDRESS=$(curl -s4m5 icanhazip.com)
    REAL_PORT=$PORT
    SEC="none"
fi

echo -e "\n--- 部署完成 (WARP: ${warp:-n}) ---"
echo "节点链接："
echo "vless://$UUID@$ADDRESS:$REAL_PORT?encryption=none&security=$SEC&sni=$ADDRESS&type=ws&host=$ADDRESS&path=%2Fws#Argo-VLESS-Speed"
