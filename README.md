# sxbot

Telegram 双向验证机器人源码，基于 `Cloudflare Workers` + `Cloudflare Pages`，实现用户与管理员的双向沟通，并通过 Turnstile 验证防止机器人滥用。完全免费部署，无需服务器。

## 关于本项目

本项目是一个简单的 Telegram Bot，用于实现用户与管理员之间的消息转发。用户首次使用时需要通过 Cloudflare Turnstile 验证，验证通过后可以向管理员发送消息，管理员可以回复用户或封禁用户。

**主要特点：**
- 完全免费部署（基于 Cloudflare 免费套餐）
- 无需服务器（Serverless 架构）
- 一键部署脚本
- 支持文本、图片、视频等多种消息类型
- 管理员群发功能

## 开始

直接运行 `deploy.bat`（Windows）或 `deploy.sh`（Linux/macOS），按照提示输入配置信息即可完成部署。

**如有任何问题，请自行研究源码或提交 Issue。**

## 前置准备

项目部署基于 `Node.js` + `Cloudflare`，你需要先准备以下内容：

1. **Node.js 环境**
   - 官网：https://nodejs.org/
   - 推荐版本：Node.js 20.x 或更高

2. **Cloudflare 账号**
   - 注册地址：https://dash.cloudflare.com/sign-up
   - 完全免费，无需信用卡

3. **Telegram Bot**
   - 与 [@BotFather](https://t.me/BotFather) 对话
   - 发送 `/newbot` 创建机器人
   - 获取 Bot Token

## 一键部署

### Windows 用户

直接双击 `deploy.bat` 文件，或在命令行运行：

```bash
deploy.bat
```

### Linux/macOS 用户

```bash
chmod +x deploy.sh
./deploy.sh
```

### 部署脚本会自动完成以下操作

- 自动创建 KV Namespace
- 交互式配置向导（Bot Token、管理员 ID、Turnstile）
- 自动设置 Workers Secrets
- 自动更新配置文件
- 构建并部署前端到 Cloudflare Pages
- 部署 Workers Bot
- 自动设置 Telegram Webhook

### 配置说明

部署脚本会引导你完成以下配置：

1. **Telegram Bot Token**：从 [@BotFather](https://t.me/BotFather) 获取
2. **管理员 Telegram ID**：你的 Telegram 用户 ID（可通过 [@QueryTokenBot](https://t.me/QueryTokenBot) 获取）
3. **Turnstile Site Key & Secret**：
   - 访问 [Cloudflare Turnstile](https://dash.cloudflare.com/?to=/:account/turnstile)
   - 点击 "Add Site" 创建站点
   - Widget Mode 选择 "Managed"
   - 域名填写脚本提示的 Pages 域名
   - 获取 Site Key 和 Secret Key

**注意：** Turnstile 域名必须填写脚本提示的 Pages 生产域名（如 `xxxxx-sx-app.pages.dev`），不支持通配符。

## 目录结构

```
sxbot/
├── frontend/                # Next.js 前端（Cloudflare Pages）
│   ├── app/
│   │   └── page.tsx        # 验证页面
│   └── package.json
├── workers/                 # Cloudflare Workers
│   ├── src/
│   │   ├── index.ts        # 入口文件
│   │   ├── types.ts        # 类型定义
│   │   ├── commands.ts     # Bot 命令处理
│   │   ├── messages.ts     # 消息处理
│   │   ├── callbacks.ts    # 回调处理
│   │   ├── api.ts          # API 端点
│   │   ├── db.ts           # KV 数据库操作
│   │   ├── utils.ts        # 工具函数
│   │   └── verification.ts # 验证逻辑
│   ├── wrangler.toml       # Workers 配置
│   └── package.json
├── scripts/
│   └── deploy.bat          # 部署脚本
├── deploy.bat              # Windows 一键部署
├── deploy.sh               # Linux/macOS 一键部署
└── README.md
```

## 使用说明

### 用户使用流程

1. 用户向机器人发送 `/start` 命令
2. 机器人检测到用户未验证，弹出验证按钮
3. 用户点击按钮打开 Mini App
4. 在 Mini App 中完成 Cloudflare Turnstile 验证
5. 验证成功后，可以向管理员发送消息
6. 支持发送文本、图片、视频等多种格式

### 管理员使用

**接收用户消息**
- 管理员会收到已验证用户发送的消息
- 消息会以转发形式显示，并附带用户信息

**回复用户**
- 直接回复用户的转发消息即可
- 机器人会自动将回复发送给用户

**封禁用户**
- 在用户消息下方点击"封禁此用户"按钮
- 被封禁用户将无法继续发送消息

**群发消息**
1. 发送 `/qf` 命令进入群发模式
2. 发送要群发的内容（支持文本、图片、视频等）
3. 确认后，消息会发送给所有用户（包括未验证用户）
4. 可以发送 `/start` 取消群发

### Bot 命令

| 命令 | 说明 | 权限 |
|------|------|------|
| `/start` | 开始使用 / 取消当前操作 | 所有用户 |
| `/qf` | 群发消息 | 仅管理员 |

## 实现逻辑

1. 用户发送消息
2. 检查用户验证状态
3. 未验证用户弹出 Mini App 验证按钮
4. 用户完成 Turnstile 验证
5. 调用 `/api/verify` 接口验证 initData 和 Turnstile token
6. 验证通过后更新 KV 数据库
7. 消息转发给管理员
8. 管理员回复消息，机器人转发给用户

## 技术栈

- **前端**：Next.js 16 + Tailwind CSS + TypeScript
- **Bot 框架**：grammY (Telegram Bot API)
- **后端**：Cloudflare Workers (Serverless)
- **数据库**：Cloudflare KV (Key-Value 存储)
- **验证**：Cloudflare Turnstile (人机验证)
- **部署**：Cloudflare Pages + Workers

## 数据存储

**用户数据** (`user:{userId}`)：
```json
{
  "id": 123456789,
  "username": "user123",
  "firstName": "张三",
  "verified": true,
  "verifiedAt": "2025-11-19T12:00:00.000Z",
  "banned": false
}
```

**消息映射** (`msg:{messageId}`)：
```
值: userId (字符串)
过期时间: 3个月 (7776000秒)
```

**管理员状态** (`admin_state:{adminId}`)：
```json
{
  "action": "broadcast",
  "messageId": 12345,
  "chatId": 67890
}
```

## 手动部署（高级用户）

如果你不想使用一键部署脚本，也可以手动部署：

### 1. 安装 Wrangler CLI

```bash
npm install -g wrangler
wrangler login
```

### 2. 创建 KV Namespace

```bash
wrangler kv namespace create KV
```

将返回的 `id` 填入 `workers/wrangler.toml`

### 3. 配置环境变量

**workers/wrangler.toml**：
```toml
[vars]
MINIAPP_URL = "https://your-project.pages.dev"
ADMIN_IDS = "your-telegram-id"

[[kv_namespaces]]
binding = "KV"
id = "your-kv-id"
```

**frontend/.env.local**：
```bash
NEXT_PUBLIC_TURNSTILE_SITE_KEY=your_site_key
NEXT_PUBLIC_API_URL=https://your-worker.workers.dev
```

### 4. 设置 Secrets

```bash
cd workers
wrangler secret put BOT_TOKEN
wrangler secret put TURNSTILE_SECRET
```

### 5. 部署

```bash
# 部署前端
cd frontend
npm install
npm run build
npx wrangler pages deploy out --project-name=your-project --branch=main

# 部署 Workers
cd ../workers
npm install
npx wrangler deploy
```

### 6. 设置 Webhook

```bash
curl -X POST "https://api.telegram.org/bot<BOT_TOKEN>/setWebhook" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://your-worker.workers.dev/webhook"}'
```

## 技术交流/意见反馈

如有任何问题或建议，欢迎提交 [Issue](https://github.com/TGlimmer/sxbot/issues)

+ MCG技术交流群 https://t.me/MCG_Club

## 私有定制

如需定制机器人或其他业务,请联系[@Miya](https://t.me/miya0v0)

## 许可证

根据 MIT 许可证分发。打开 [LICENSE](LICENSE) 查看更多内容。

<p align="right">(<a href="#top">返回顶部</a>)</p>
