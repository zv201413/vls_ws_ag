#!/bin/bash

# --- 1. 基础配置 ---
WORK_DIR="/home/zv/vless-all"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# --- 2. 核心：卸载模块 ---
if [ "$1" = "uninstall" ]; then
    echo "正在彻底卸载服务..."
    pkill -f xray
    pkill -f cloudflared
    cd /home/zv && rm -rf "$WORK_DIR"
    echo "卸载完成！所有进程已停止，目录已删除。"
    exit 0
fi

# --- 3. 环境准备 ---
[ -f "cloudflared" ] || { echo "下载 Argo..."; curl -L -o cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x cloudflared; }
[ -f "xray" ] || { echo "下载 Xray..."; curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && unzip -o xray.zip && chmod +x xray; }

# --- 4. WARP 密钥获取与容错 ---
OUTBOUND_JSON='{ "protocol": "freedom", "settings": { "domainStrategy": "UseIP" } }'

if [ "$warp" = "y" ]; then
    echo "正在获取云端 WARP 密钥..."
    # 尝试从甬哥接口获取
    warp_raw=$(curl -sL "https://warp.xijp.eu.org")
    
    # 检查接口是否有效 (不包含 html 且内容不为空)
    if [ -n "$warp_raw" ] && ! echo "$warp_raw" | grep -q "html"; then
        pvk=$(echo "$warp_raw" | grep "Private_key" | awk -F'：' '{print $2}' | tr -d ' \r')
        wpv6=$(echo "$warp_raw" | grep "IPV6" | awk -F'：' '{print $2}' | tr -d ' \r')
        res=$(echo "$warp_raw" | grep "reserved" | awk -F'：' '{print $2}' | tr -d '[] \r')
        echo "已成功从云端提取 WARP 密钥"
    else
        # 触发兜底逻辑
        echo "云端接口不可用，启用硬编码兜底密钥..."
        pvk='52cuYFgCJXp0LAq7+nWJIbCXXgU9eGggOc+Hlfz5u6A='
        wpv6='2606:4700:110:8d8d:1845:c39f:2dd5:a03a'
        res='215, 69, 233'
    fi

    OUTBOUND_JSON='{
        "protocol": "wireguard",
        "settings": {
            "secretKey": "'$pvk'",
            "address": ["172.16.0.2/32", "'$wpv6'/128"],
            "peers": [{
                "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
                "endpoint": "engage.cloudflareclient.com:2408"
            }],
            "reserved": ['$res']
        }
    }'
    echo "WARP 出站配置已就绪"
fi

# --- 5. 生成 Xray 配置 ---
cat << JSON > config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 8003, "protocol": "vless",
    "settings": { "clients": [{"id": "8e6290c1-b97e-40c0-b9a3-7e7ed11ce248"}], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "/ws" } }
  }],
  "outbounds": [$OUTBOUND_JSON]
}
JSON

# --- 6. 启动服务 ---
pkill -f xray
pkill -f cloudflared
# 确保启动前日志为空，防止读取到旧域名
rm -f argo.log && touch argo.log

nohup ./xray -c config.json > xray.log 2>&1 &
nohup ./cloudflared tunnel --url http://localhost:8003 --no-autoupdate > argo.log 2>&1 &

# --- 7. 智能获取域名链接 ---
echo "正在等待 Argo 隧道分配域名 (最多等待 30 秒)..."
ITERATION=0
DOMAIN=""
while [ -z "$DOMAIN" ] && [ $ITERATION -lt 15 ]; do
    sleep 2
    # 增加文件存在检查，修复 grep 报错
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
    echo -e "\n警告：Argo 隧道启动超时，切换至 IP 直连模式。"
fi

echo -e "\n--- 部署完成 (WARP: ${warp:-n}) ---"
echo "节点链接："
echo "vless://8e6290c1-b97e-40c0-b9a3-7e7ed11ce248@$ADDRESS:$PORT_LINK?encryption=none&security=$SEC&sni=$ADDRESS&type=ws&host=$ADDRESS&path=%2Fws#Argo-VLESS"
