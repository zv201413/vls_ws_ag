cat << 'EOF' > run_vless.sh
#!/bin/bash

# --- 配置区 ---
WORK_DIR="/home/zv/vless-all"
CONFIG_FILE="$WORK_DIR/config.json"
UUID="8e6290c1-b97e-40c0-b9a3-7e7ed11ce248"
PORT=8003

# --- 逻辑处理：根据环境变量决定出站 ---
# 如果执行时带了 warp=y，则出站标签设为 warp，否则设为 direct
if [ "$warp" = "y" ]; then
    OUTBOUND_TYPE="wireguard"
    OUTBOUND_TAG="warp"
    echo "检测到 warp=y，将配置 WARP 链式出站..."
else
    OUTBOUND_TYPE="freedom"
    OUTBOUND_TAG="direct"
    echo "未检测到环境变量，使用常规直接出站..."
fi

# --- 生成配置文件 ---
mkdir -p $WORK_DIR
cat << JSON > $CONFIG_FILE
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$UUID"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/ws" }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "$OUTBOUND_TAG",
      "protocol": "$OUTBOUND_TYPE",
      "settings": {
        $( [ "$warp" = "y" ] && echo '
          "secretKey": "你的WARP私钥",
          "address": ["172.16.0.2/32"],
          "peers": [{ "publicKey": "WARP公钥", "endpoint": "engage.cloudflareclient.com:2408" }]
        ' || echo '"domainStrategy": "UseIP"')
      }
    }
  ]
}
JSON

# --- 运行服务 ---
pkill -f xray
nohup $WORK_DIR/xray -c $CONFIG_FILE > /dev/null 2>&1 &

# --- 自动生成订阅链接 ---
# 尝试获取公网IP，如果获取不到则提示手动替换
IP=$(curl -sS4m5 icanhazip.com || echo "YOUR_IP")
echo -e "\n--- 部署成功 ---"
echo "节点链接 (直接出站):"
echo "vless://$UUID@$IP:$PORT?encryption=none&security=none&type=ws&host=$IP&path=%2Fws#VLESS-Direct"
EOF

chmod +x run_vless.sh
