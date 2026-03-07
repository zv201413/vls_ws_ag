#!/bin/bash
# ====================================================
# 定制版: VLESS (去除enc) + 多协议全家桶 + Argo 隧道
# ====================================================
export LANG=en_US.UTF-8
WORK_DIR="$HOME/vless-all"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR" || exit

echo "=================================================="
echo "开始安装 VLESS 全家桶 (无加密版) + Argo Tunnel"
echo "=================================================="

# 1. 安装基础依赖
echo "[1/6] 检查并安装必要依赖 (curl, wget, unzip, jq)..."
if command -v apt >/dev/null 2>&1; then
    apt update -y >/dev/null 2>&1
    apt install -y curl wget unzip jq >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget unzip jq >/dev/null 2>&1
fi

# 2. 核心架构检测与 Xray 下载 (移植自甬哥脚本)
echo "[2/6] 下载 Xray 内核..."
arch=$(uname -m)
case $arch in
    x86_64) xray_arch="64" ;;
    aarch64) xray_arch="arm64-v8a" ;;
    *) echo "错误: 不支持的架构 $arch"; exit 1 ;;
esac

XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${xray_arch}.zip"
rm -f /tmp/xray.zip
if command -v curl >/dev/null 2>&1; then
    curl -LSs -o /tmp/xray.zip "$XRAY_URL"
else
    wget -qO /tmp/xray.zip "$XRAY_URL"
fi

rm -rf /tmp/xray_temp && mkdir -p /tmp/xray_temp
unzip -q -o /tmp/xray.zip -d /tmp/xray_temp
xray_bin=$(find /tmp/xray_temp -type f -name "xray" | head -n 1)
if [ -z "$xray_bin" ]; then
    echo "错误：压缩包内未找到 xray"
    exit 1
fi
mv "$xray_bin" "$WORK_DIR/xray"
chmod +x "$WORK_DIR/xray"
rm -rf /tmp/xray*

# 3. 下载 Cloudflared
echo "[3/6] 下载 Cloudflared..."
case $arch in
    x86_64) cf_arch="amd64" ;;
    aarch64) cf_arch="arm64" ;;
esac
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}"
if command -v curl >/dev/null 2>&1; then
    curl -LSs -o "$WORK_DIR/cloudflared" "$CF_URL"
else
    wget -qO "$WORK_DIR/cloudflared" "$CF_URL"
fi
chmod +x "$WORK_DIR/cloudflared"

# 4. 生成 Xray 配置文件 (去除 VLESS 加密，即 decryption: none)
echo "[4/6] 生成 Xray 配置文件..."
UUID=$(cat /proc/sys/kernel/random/uuid)
# 生成 Reality 密钥对
keys=$("$WORK_DIR/xray" x25519)
PRIVATE_KEY=$(echo "$keys" | grep "Private key:" | awk '{print $3}')
PUBLIC_KEY=$(echo "$keys" | grep "Public key:" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

cat > "$WORK_DIR/config.json" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    { "port": 8001, "protocol": "vless", "settings": { "clients": [{"id": "$UUID"}], "decryption": "none" }, "streamSettings": { "network": "tcp" } },
    { "port": 8002, "protocol": "vless", "settings": { "clients": [{"id": "$UUID"}], "decryption": "none" }, "streamSettings": { "network": "tcp", "security": "reality", "realitySettings": { "show": false, "dest": "www.microsoft.com:443", "xver": 0, "serverNames": ["www.microsoft.com"], "privateKey": "$PRIVATE_KEY", "shortIds": ["$SHORT_ID"] } } },
    { "port": 8003, "protocol": "vless", "settings": { "clients": [{"id": "$UUID"}], "decryption": "none" }, "streamSettings": { "network": "ws", "wsSettings": { "path": "/ws" } } },
    { "port": 8004, "protocol": "vless", "settings": { "clients": [{"id": "$UUID"}], "decryption": "none" }, "streamSettings": { "network": "ws", "security": "tls", "tlsSettings": { "certificates": [{"certificateFile": "", "keyFile": ""}] }, "wsSettings": { "path": "/wstls" } } },
    { "port": 8005, "protocol": "vless", "settings": { "clients": [{"id": "$UUID"}], "decryption": "none" }, "streamSettings": { "network": "tcp", "tcpSettings": { "header": { "type": "http", "request": { "path": ["/"] } } } } },
    { "port": 8006, "protocol": "vless", "settings": { "clients": [{"id": "$UUID"}], "decryption": "none" }, "streamSettings": { "network": "tcp", "security": "tls", "tlsSettings": { "certificates": [{"certificateFile": "", "keyFile": ""}] }, "tcpSettings": { "header": { "type": "http", "request": { "path": ["/"] } } } } }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 5. 启动服务
echo "[5/6] 启动 Xray 与 Argo 隧道..."
pkill -f xray
pkill -f cloudflared
sleep 1

nohup "$WORK_DIR/xray" -c "$WORK_DIR/config.json" >/dev/null 2>&1 &
# 隧道指向 8003 (WebSocket 端口)，因为 CF 隧道原生最完美支持 WS 穿透
nohup "$WORK_DIR/cloudflared" tunnel --url http://localhost:8003 --edge-ip-version auto --no-autoupdate --protocol http2 > "$WORK_DIR/argo.log" 2>&1 &

echo "等待 Argo 分配域名 (约需 10 秒)..."
sleep 10
ARGO_DOMAIN=$(grep -a trycloudflare.com "$WORK_DIR/argo.log" 2>/dev/null | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')

if [ -z "$ARGO_DOMAIN" ]; then
    echo "⚠️ Argo 域名获取失败，可能由于网络延迟。你可以稍后查看 argo.log 获取。"
    ARGO_DOMAIN="your-argo-domain.trycloudflare.com"
fi

# 6. 打印节点信息
echo "=================================================="
echo "部署成功！以下是你的 6 种 VLESS 节点链接 (均无加密层)"
echo "UUID: $UUID"
echo "=================================================="

# 1. VLESS+TCP
echo -e "\n1. VLESS+TCP (无加密，速度最快 - 需使用本地 Cloudflared 客户端挂载)"
echo "vless://${UUID}@${ARGO_DOMAIN}:80?encryption=none&security=none&type=tcp#VLESS-TCP"

# 2. VLESS+TCP+TLS (Reality)
echo -e "\n2. VLESS+TCP+TLS (Reality，安全+速度 - 需使用本地 Cloudflared 客户端挂载)"
echo "vless://${UUID}@${ARGO_DOMAIN}:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp#VLESS-Reality"

# 3. VLESS+WebSocket (重点推荐，Argo完美穿透)
echo -e "\n3. VLESS+WebSocket (无加密，CDN友好 - 可直接连，Argo自带外层TLS)"
echo "vless://${UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&type=ws&host=${ARGO_DOMAIN}&path=%2Fws#VLESS-WS"

# 4. VLESS+WebSocket+TLS
echo -e "\n4. VLESS+WebSocket+TLS (带双重TLS)"
echo "vless://${UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&type=ws&host=${ARGO_DOMAIN}&path=%2Fwstls#VLESS-WS-TLS"

# 5. VLESS+HTTP
echo -e "\n5. VLESS+HTTP (无加密HTTP伪装)"
echo "vless://${UUID}@${ARGO_DOMAIN}:80?encryption=none&security=none&type=tcp&headerType=http#VLESS-HTTP"

# 6. VLESS+HTTP+TLS
echo -e "\n6. VLESS+HTTP+TLS (带TLS)"
echo "vless://${UUID}@${ARGO_DOMAIN}:443?encryption=none&security=tls&sni=${ARGO_DOMAIN}&type=tcp&headerType=http#VLESS-HTTP-TLS"

echo "=================================================="
echo "💡 提示："
echo "如果想要免配本地客户端直接在手机/电脑连接，请首选使用 第 3 个节点 (VLESS+WebSocket)。"
echo "=================================================="
