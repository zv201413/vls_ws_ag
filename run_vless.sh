cat << 'EOF' > run_vless.sh
#!/bin/bash

WORK_DIR="/home/zv/vless-all"
CONFIG_FILE="$WORK_DIR/config.json"
UUID="8e6290c1-b97e-40c0-b9a3-7e7ed11ce248"
PORT=8003

# --- 自动化 WARP 注册函数 ---
generate_warp_conf() {
    echo "正在自动获取 WARP 账户信息..."
    # 使用 wgcf 或直接调用 API 模拟注册 (这里使用简化的模拟 API 调用)
    auth=$(curl -sX POST "https://api.cloudflareclient.com/v0a1922/reg" -H "Content-Type: application/json" -d '{"install_id":"","tos":"2020-01-22T00:00:00.000Z","key":"'$(wg genkey | tee /tmp/priv | wg pubkey)'","fcm_token":""}')
    
    W_PRIV=$(cat /tmp/priv)
    W_PUB=$(echo "$auth" | grep -oE '"public_key":"[^"]+"' | cut -d'"' -f4)
    W_V6=$(echo "$auth" | grep -oE '"v6":"[^"]+"' | cut -d'"' -f4)
    
    # 获取 Reserved 字节 (甬哥脚本提速的关键)
    W_RES=$(curl -sX GET "https://api.cloudflareclient.com/v0a1922/reg/$(echo "$auth" | grep -oE '"id":"[^"]+"' | cut -d'"' -f4)" -H "Authorization: Bearer $(echo "$auth" | grep -oE '"token":"[^"]+"' | cut -d'"' -f4)" | grep -oE '"reserved":\[[0-9, ]+\]' | cut -d: -f2)
    
    echo "WARP 分配完成。"
}

# --- 逻辑处理 ---
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
    OUTBOUND_JSON='{
      "protocol": "freedom",
      "settings": { "domainStrategy": "UseIP" }
    }'
fi

# --- 生成并运行 ---
mkdir -p $WORK_DIR
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
nohup $WORK_DIR/xray -c $CONFIG_FILE > /dev/null 2>&1 &
echo "服务已启动，WARP 状态: ${warp:-n}"
EOF

chmod +x run_vless.sh
