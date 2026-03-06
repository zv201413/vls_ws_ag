#!/bin/sh
# VLESS-TS-Argo 一键安装入口
# 功能: 自动检测环境并安装最新版

REPO="https://github.com/zv201413/vless-ts"
SCRIPT_URL="${REPO}/releases/latest/download/vless-ts.sh"

GREEN='\033[0;32m'
NC='\033[0m'

print_banner() {
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║     VLESS + TCP + Reality + Argo 一键安装脚本          ║"
echo "║     版本: V1.0.0 | 无加密层(enc) | 原生 Reality       ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
}

print_usage() {
echo "${GREEN}【使用方法】${NC}"
echo ""
echo "1. 基础安装 (仅 Reality 直连):"
echo "   ${GREEN}vlpt=8443 bash install.sh${NC}"
echo ""
echo "2. 临时 Argo 隧道 (被墙VPS推荐):"
echo "   ${GREEN}vlpt=8443 argo=vlpt bash install.sh${NC}"
echo ""
echo "3. 固定 Argo 隧道 (最佳体验):"
echo "   先去 https://dash.cloudflare.com 创建隧道得到 token"
echo "   ${GREEN}vlpt=8443 argo=vlpt agn=xxx.trycloudflare.com agk=eyJ... bash install.sh${NC}"
echo ""
echo "可选参数:"
echo "   uuid=xxx        自定义 UUID"
echo "   reym=xxx.com    自定义 SNI 域名 (默认 www.cloudflare.com)"
echo ""
}

# 检查必要命令
check_deps() {
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo "错误: 需要 curl 或 wget"
        exit 1
    fi
    
    if ! command -v unzip >/dev/null 2>&1; then
        echo "安装 unzip..."
        apt-get update >/dev/null 2>&1 && apt-get install -y unzip 2>/dev/null || \
        yum install -y unzip 2>/dev/null || \
        echo "请手动安装 unzip"
    fi
}

# 下载并执行主脚本
main() {
    print_banner
    
    # 检查是否直接运行
    if [ -z "${vlpt+x}" ] && [ -z "${ARGV0}" ]; then
        print_usage
        exit 0
    fi
    
    check_deps
    
    echo "正在下载主脚本..."
    SAVE_PATH="$HOME/vless-ts.sh"
    
    if command -v curl >/dev/null 2>&1; then
        curl -sLo "$SAVE_PATH" "$SCRIPT_URL"
    else
        wget -qO "$SAVE_PATH" "$SCRIPT_URL"
    fi
    
    if [ ! -f "$SAVE_PATH" ]; then
        echo "下载失败，请检查网络"
        exit 1
    fi
    
    chmod +x "$SAVE_PATH"
    
    # 传递环境变量并执行
    export vlpt="${vlpt:-}"
    export argo="${argo:-}"
    export agn="${agn:-}"
    export agk="${agk:-}"
    export uuid="${uuid:-}"
    export reym="${reym:-}"
    
    echo "正在安装..."
    echo "----------------------------------------"
    sh "$SAVE_PATH"
}

main
