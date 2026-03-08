#!/bin/bash

# --- 1. 基础配置 ---
WORK_DIR="/home/zv/vless-all"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# --- 2. 卸载功能 ---
if [ "$1" = "uninstall" ]; then
    echo "正在彻底卸载服务..."
    pkill -f xray
    pkill -f cloudflared
    cd /home/zv && rm -rf "$WORK_DIR"
    echo "卸载完成！所有进程已停止，目录已删除。"
    exit 0
fi

# --- 3. 环境准备 ---
echo "检查运行环境..."
[ -f "cloudflared" ] || { echo "下载 Argo..."; curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x cloudflared; }
[ -f "xray" ] || { echo "下载 Xray..."; curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && unzip -o xray.zip && chmod +x xray; }
chmod +x cloudflared xray

# --- 4. WARP 密钥与策略构建 ---
# 默认直连
OUTBOUNDS_JSON='{ "protocol": "freedom", "tag": "direct", "settings": { "domainStrategy": "UseIP" } }'
ROUTING_RULE='{ "type": "field", "outboundTag": "direct", "network": "tcp,udp" }'

if [ "$warp" = "y" ]; then
    echo "正在尝试获取云端 WARP 密钥..."
    warp_raw=$(curl -sL "https://warp.xijp.eu.org")
    
    if [ -n "$warp_raw" ] && ! echo "$warp_raw" | grep -q "html"; then
        pvk=$(echo "$warp_raw" | grep "Private_key" | awk -F'：' '{print $2}' | tr -d ' \r')
        wpv6=$(echo "$warp_raw" | grep "IPV6" | awk -F'：' '{print $2}' | tr -d ' \r')
        res=$(echo "$warp_raw" | grep "reserved" | awk -F'：' '{print $2}' | tr -d '[] \r')
        echo "已从云端提取最新密钥"
    else
        # 使用你提供的兜底配置
        echo "云端获取失败，应用指定的兜底配置..."
        pvk='sBbO/ohZrLRoSFRaQCciqyiRFHwbxZ88nlDO5vNmD2I='
        wpv6='2606:4700:110:8515:e070:6396:54b0:15ba'
        res='0, 0, 0'
    fi

    # 构建 V6 优先的 WARP 出站结构
    OUTBOUNDS_JSON='
    {
      "tag": "x-warp-out",
      "protocol": "wireguard",
      "settings": {
        "secretKey": "'$pvk'",
        "address": ["172.16.0.2/32", "'$wpv6'/128"],
        "peers": [{
          "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "endpoint": "162.159.192.1:2408" 
        }],
        "reserved": ['$res'],
        "mtu": 1280
      }
    },
    {
      "tag": "warp-v6-out",
      "protocol": "freedom",
      "settings": { "domainStrategy": "ForceIPv6" },
      "proxySettings": { "tag": "x-warp-out" }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": { "domainStrategy": "UseIPv4" }
    }'
    
    ROUTING_RULE='{ "type": "field", "outboundTag": "warp-v6-out", "network": "tcp,udp" }'
    echo "WARP IPv6 优先配置已就绪"
fi

# --- 5. 生成 Xray 配置文件 ---
cat << JSON > config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 8003,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "8e6290c1-b97e-40c0-b9a3-7e7ed11ce248"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "/ws" }
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls", "quic"]
    }
  }],
  "outbounds": [$OUTBOUNDS_JSON],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [$ROUTING_RULE]
  }
}
JSON

# --- 6. 启动进程 ---
echo "正在重启服务..."
pkill -f xray
pkill -f cloudflared
rm -f argo.log && touch argo.log

nohup ./xray -c config.json > xray.log 2>&1 &
nohup ./cloudflared tunnel --url http://localhost:8003 --no-autoupdate > argo.log 2>&1 &

# --- 7. 获取域名与链接 ---
echo "等待域名分配..."
ITERATION=0
DOMAIN=""
while [ -z "$DOMAIN" ] && [ $ITERATION -lt 15 ]; do
    sleep 2
    if [ -f "argo.log" ]; then
        DOMAIN=$(grep -oE 'https://[a-z0-9.-]+\.trycloudflare\.com' argo.log | tail -n 1 | sed 's/https:\/\///')
    fi
    ITERATION=$((ITERATION+1))
    echo -n "."
done

if [ -n "$DOMAIN" ]; then
    ADDRESS=$DOMAIN
    PORT_LINK=443
    SEC="tls"
else
    ADDRESS=$(curl -s4 icanhazip.com)
    PORT_LINK=8003
    SEC="none"
    echo -e "\n[!] Argo 隧道分配失败，已回退至 IP 直连。"
fi

echo -e "\n--- 部署成功 ---"
echo "WARP 状态: ${warp:-n}"
echo "节点链接 (点击复制)："
echo "vless://8e6290c1-b97e-40c0-b9a3-7e7ed11ce248@$ADDRESS:$PORT_LINK?encryption=none&security=$SEC&sni=$ADDRESS&type=ws&host=$ADDRESS&path=%2Fws#Argo-WARP-IPv6"
