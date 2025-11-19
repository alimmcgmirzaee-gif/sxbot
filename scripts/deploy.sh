#!/bin/bash

set -e

# 确保从项目根目录执行
cd "$(dirname "$0")/.."

echo "================================"
echo "sxbot 部署脚本"
echo "================================"
echo ""

# 检测 wrangler 命令
WRANGLER_CMD="wrangler"
if ! command -v wrangler &> /dev/null; then
    echo "提示: 未检测到全局 wrangler，尝试使用 npx"
    WRANGLER_CMD="npx wrangler"
    
    if ! command -v npx &> /dev/null; then
        echo "错误: 未找到 wrangler 和 npx"
        echo ""
        echo "请先安装 Cloudflare Wrangler CLI:"
        echo ""
        echo "方法1: 使用 npm 全局安装"
        echo "   npm install -g wrangler"
        echo ""
        echo "方法2: 使用 npx"
        echo "   npx wrangler"
        echo ""
        exit 1
    fi
fi

# 检查 npm
if ! command -v npm &> /dev/null; then
    echo "错误: 未找到 npm"
    echo ""
    echo "请先安装 Node.js:"
    echo "下载地址: https://nodejs.org/"
    echo ""
    exit 1
fi

echo "步骤1: 部署前端"
echo ""

FRONTEND_DEPLOYED=0

if [ ! -d "frontend" ]; then
    echo "未检测到 frontend 目录，跳过前端部署"
    echo ""
else
    read -p "是否跳过前端部署? (y/n，默认 n): " SKIP_FRONTEND
    if [ "$SKIP_FRONTEND" = "y" ] || [ "$SKIP_FRONTEND" = "Y" ]; then
        echo "跳过前端部署"
    else
        FRONTEND_DEPLOYED=1
        
        cd frontend
        
        if [ ! -f "package.json" ]; then
            echo "警告: 未找到 frontend/package.json"
            cd ..
        else
            if [ ! -d "node_modules" ]; then
                echo "安装前端依赖..."
                npm install
            fi
            
            echo "构建 Next.js..."
            npm run build
            
            echo "部署到 Cloudflare Pages..."
            echo "正在从 Cloudflare 获取已有项目..."
            
            # 从 Cloudflare 拉取现有项目
            PAGES_PROJECT_NAME=""
            TEMP_LIST=$($WRANGLER_CMD pages project list 2>&1 || true)
            
            # 查找包含 sx-app 的项目名
            while IFS= read -r line; do
                if echo "$line" | grep -q "sx-app"; then
                    # 提取项目名（去除表格符号和空格）
                    PROJECT_NAME=$(echo "$line" | awk -F'│' '{print $2}' | tr -d ' ' | grep -v '^$' | grep -v 'Project' | grep -v 'Name' | head -n1)
                    if [ -n "$PROJECT_NAME" ] && [ "$PROJECT_NAME" != "ProjectName" ]; then
                        PAGES_PROJECT_NAME="$PROJECT_NAME"
                        break
                    fi
                fi
            done <<< "$TEMP_LIST"
            
            if [ -n "$PAGES_PROJECT_NAME" ]; then
                echo "找到已有项目: $PAGES_PROJECT_NAME"
            else
                # 创建新项目名
                RANDOM_SUFFIX=$((RANDOM % 90000 + 10000))
                PAGES_PROJECT_NAME="${RANDOM_SUFFIX}-sx-app"
                echo "创建新项目: $PAGES_PROJECT_NAME"
            fi
            
            echo ""
            $WRANGLER_CMD pages deploy out --project-name="$PAGES_PROJECT_NAME" --branch=main
            
            echo "成功: 前端部署完成"
            echo "URL: https://${PAGES_PROJECT_NAME}.pages.dev"
            echo "项目名: $PAGES_PROJECT_NAME"
            echo ""
            
            cd ..
        fi
    fi
fi

echo "步骤2: 部署 Workers"
echo ""

# 如果前端被跳过且没有项目名，尝试从 Cloudflare 获取
if [ -z "$PAGES_PROJECT_NAME" ]; then
    echo "正在获取 Pages 项目信息..."
    TEMP_LIST=$($WRANGLER_CMD pages project list 2>&1 || true)
    while IFS= read -r line; do
        if echo "$line" | grep -q "sx-app"; then
            PROJECT_NAME=$(echo "$line" | awk -F'│' '{print $2}' | tr -d ' ' | grep -v '^$' | grep -v 'Project' | grep -v 'Name' | head -n1)
            if [ -n "$PROJECT_NAME" ] && [ "$PROJECT_NAME" != "ProjectName" ]; then
                PAGES_PROJECT_NAME="$PROJECT_NAME"
                echo "找到 Pages 项目: $PAGES_PROJECT_NAME"
                echo ""
                break
            fi
        fi
    done <<< "$TEMP_LIST"
fi

cd workers

if [ ! -f "package.json" ]; then
    echo "警告: 未找到 workers/package.json"
    cd ..
    exit 0
fi

# 检查配置状态
echo "================================"
echo "检查配置..."
echo "================================"
echo ""

CONFIG_NEEDED=0

# 检查 ADMIN_IDS
if grep -q "123456789" wrangler.toml; then
    echo "检测到默认管理员 ID，需要配置"
    CONFIG_NEEDED=1
fi

# 检查是否已设置 BOT_TOKEN secret
if ! $WRANGLER_CMD secret list 2>/dev/null | grep -q "BOT_TOKEN"; then
    echo "检测到未设置 Bot Token，需要配置"
    CONFIG_NEEDED=1
fi

# 检查是否已设置 TURNSTILE_SECRET
if ! $WRANGLER_CMD secret list 2>/dev/null | grep -q "TURNSTILE_SECRET"; then
    echo "检测到未设置 Turnstile Secret，需要配置"
    CONFIG_NEEDED=1
fi

if [ $CONFIG_NEEDED -eq 1 ]; then
    echo "================================"
    echo "首次部署配置向导"
    echo "================================"
    echo ""
    
    # 输入 Telegram Bot Token
    echo "[1/4] Telegram Bot 配置"
    read -p "请输入 Telegram Bot Token: " INPUT_BOT_TOKEN
    if [ -z "$INPUT_BOT_TOKEN" ]; then
        echo "错误: Bot Token 不能为空"
        exit 1
    fi
    echo ""
    
    # 输入管理员 Telegram ID
    echo "[2/4] 管理员配置"
    read -p "请输入管理员 Telegram 用户 ID: " INPUT_ADMIN_ID
    if [ -z "$INPUT_ADMIN_ID" ]; then
        echo "错误: 管理员 ID 不能为空"
        exit 1
    fi
    echo ""
    
    # Turnstile 配置
    echo "[3/4] Turnstile 配置 (必填，用于防机器人)"
    echo ""
    echo "请先在 Cloudflare Dashboard 创建 Turnstile 站点:"
    echo ""
    echo "1. 访问: https://dash.cloudflare.com/?to=/:account/turnstile"
    echo "2. 点击 \"Add Site\" 创建站点"
    if [ -n "$PAGES_PROJECT_NAME" ]; then
        echo "3. 在 Domains 字段中填写: ${PAGES_PROJECT_NAME}.pages.dev"
    else
        echo "3. 在 Domains 字段中填写你的 Pages 域名"
    fi
    echo "4. Widget Mode 选择: Managed"
    echo "5. 复制 Site Key 和 Secret Key"
    echo ""
    read -p "请输入 Turnstile Secret Key: " INPUT_TURNSTILE_SECRET
    if [ -z "$INPUT_TURNSTILE_SECRET" ]; then
        echo "错误: Turnstile Secret Key 不能为空"
        exit 1
    fi
    read -p "请输入 Turnstile Site Key: " INPUT_TURNSTILE_SITE
    if [ -z "$INPUT_TURNSTILE_SITE" ]; then
        echo "错误: Turnstile Site Key 不能为空"
        exit 1
    fi
    echo ""
    
    # 前端项目配置
    echo "[4/4] 前端项目配置"
    if [ -n "$PAGES_PROJECT_NAME" ]; then
        echo "前端域名: ${PAGES_PROJECT_NAME}.pages.dev"
    else
        echo "警告: 未检测到前端项目名"
    fi
    echo ""
    
    echo "================================"
    echo "正在应用配置..."
    echo "================================"
    echo ""
    
    # 更新 ADMIN_IDS
    echo "[1/4] 更新管理员 ID..."
    sed -i.bak "s/ADMIN_IDS = \"123456789\"/ADMIN_IDS = \"$INPUT_ADMIN_ID\"/" wrangler.toml
    rm -f wrangler.toml.bak
    
    # 更新 MINIAPP_URL
    if [ -n "$PAGES_PROJECT_NAME" ]; then
        echo "更新前端 URL..."
        sed -i.bak "s|MINIAPP_URL = \"https://.*\.pages\.dev\"|MINIAPP_URL = \"https://${PAGES_PROJECT_NAME}.pages.dev\"|" wrangler.toml
        rm -f wrangler.toml.bak
    fi
    
    # 设置 BOT_TOKEN secret
    echo "[2/4] 设置 Bot Token..."
    echo "$INPUT_BOT_TOKEN" | $WRANGLER_CMD secret put BOT_TOKEN
    
    # 设置 TURNSTILE_SECRET
    echo "[3/4] 设置 Turnstile Secret..."
    echo "$INPUT_TURNSTILE_SECRET" | $WRANGLER_CMD secret put TURNSTILE_SECRET
    
    # 创建前端配置文件
    echo "[4/4] 创建前端环境变量..."
    cd ..
    if [ -d "frontend" ]; then
        cat > frontend/.env.local <<EOF
NEXT_PUBLIC_API_URL=https://sxbot-bot.workers.dev
NEXT_PUBLIC_TURNSTILE_SITE_KEY=$INPUT_TURNSTILE_SITE
EOF
        echo "前端环境变量已创建（Workers URL 将在部署后自动更新）"
    fi
    cd workers
    
    echo ""
    echo "配置完成"
    echo ""
else
    echo "✅ 配置检查通过，跳过配置向导"
    echo ""
fi

# 安装 Workers 依赖
if [ ! -d "node_modules" ]; then
    echo "安装 Workers 依赖..."
    npm install
fi

# 检查是否需要创建 KV Namespace
if grep -q "YOUR_KV_NAMESPACE_ID" wrangler.toml; then
    echo "检测到未配置 KV Namespace，正在创建..."
    echo ""
    KV_OUTPUT=$($WRANGLER_CMD kv namespace create KV)
    KV_ID=$(echo "$KV_OUTPUT" | grep "id = " | awk '{print $3}' | tr -d '"')
    
    if [ -z "$KV_ID" ]; then
        echo "错误: 无法创建 KV Namespace"
        exit 1
    fi
    
    echo "KV Namespace 创建成功，ID: $KV_ID"
    echo "正在自动更新 wrangler.toml..."
    
    sed -i.bak "s/YOUR_KV_NAMESPACE_ID/$KV_ID/" wrangler.toml
    rm -f wrangler.toml.bak
    
    echo "配置已更新"
    echo ""
fi

echo "部署 Workers..."

# 部署并捕获输出
DEPLOY_OUTPUT=$($WRANGLER_CMD deploy 2>&1)
echo "$DEPLOY_OUTPUT"

# 提取 Workers URL
ACTUAL_WORKERS_URL=$(echo "$DEPLOY_OUTPUT" | grep -o "https://[a-zA-Z0-9-]*\.workers\.dev" | head -n1)

if [ -z "$ACTUAL_WORKERS_URL" ]; then
    echo "警告: 无法自动获取 Workers URL"
    ACTUAL_WORKERS_URL="未知"
fi

echo "成功: Workers 部署完成"
echo "Workers URL: $ACTUAL_WORKERS_URL"
echo ""

# 更新前端配置
if [ -f "../frontend/.env.local" ] && [ "$ACTUAL_WORKERS_URL" != "未知" ]; then
    echo "正在更新前端配置..."
    sed -i.bak "s|NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=$ACTUAL_WORKERS_URL|" ../frontend/.env.local
    rm -f ../frontend/.env.local.bak
    echo "前端本地配置已更新"
    echo ""
    echo "⚠️ Workers URL 已更新，需要重新构建并部署前端:"
    echo "   cd frontend"
    echo "   npm run build"
    echo "   $WRANGLER_CMD pages deploy out --project-name=$PAGES_PROJECT_NAME --branch=main"
    echo ""
fi

cd ..

echo "================================"
echo "部署完成"
echo "================================"
echo ""

echo "步骤3: 设置 Webhook"
echo ""

# 自动设置 Webhook
if [ -n "$INPUT_BOT_TOKEN" ] && [ "$ACTUAL_WORKERS_URL" != "未知" ]; then
    echo "自动设置 Webhook..."
    WEBHOOK_URL="${ACTUAL_WORKERS_URL}/webhook"
    echo "URL: $WEBHOOK_URL"
    
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${INPUT_BOT_TOKEN}/setWebhook" \
        -H "Content-Type: application/json" \
        -d "{\"url\": \"${WEBHOOK_URL}\"}")
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo "Webhook 设置成功"
    else
        echo "Webhook 设置失败"
        echo "$RESPONSE"
    fi
    echo ""
fi

echo "================================"
echo "部署总结"
echo "================================"
echo ""
echo "✅ Workers 已部署并运行"
if [ "$ACTUAL_WORKERS_URL" != "未知" ]; then
    echo "   Workers URL: $ACTUAL_WORKERS_URL"
fi
echo ""
echo "✅ 前端已部署"
if [ -n "$PAGES_PROJECT_NAME" ]; then
    echo "   Pages URL: https://${PAGES_PROJECT_NAME}.pages.dev"
else
    echo "   Pages URL: https://xxxxx-sx-app.pages.dev"
fi
echo ""
echo "✅ Turnstile 验证已配置"
if [ -n "$PAGES_PROJECT_NAME" ]; then
    echo "   站点域名: ${PAGES_PROJECT_NAME}.pages.dev"
else
    echo "   站点域名: xxxxx-sx-app.pages.dev"
fi
echo ""
echo "💡 重要提示:"
echo ""
echo "1. 确保 Turnstile 站点域名设置正确"
echo "   访问: https://dash.cloudflare.com/?to=/:account/turnstile"
if [ -n "$PAGES_PROJECT_NAME" ]; then
    echo "   Domains 字段应填写: ${PAGES_PROJECT_NAME}.pages.dev"
else
    echo "   Domains 字段应填写: 你的Pages域名"
fi
echo "   (不要加 https:// 或其他前缀)"
echo ""
echo "2. 如需更新配置，可运行:"
echo "   cd workers"
echo "   $WRANGLER_CMD secret put BOT_TOKEN"
echo "   $WRANGLER_CMD secret put TURNSTILE_SECRET"
echo ""
echo "3. 查看 Bot 日志:"
echo "   cd workers"
echo "   $WRANGLER_CMD tail"
echo ""
