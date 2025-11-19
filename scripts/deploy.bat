@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

REM 确保从项目根目录执行
cd /d "%~dp0\.."

echo ================================
echo sxbot 部署脚本
echo ================================
echo.

REM 检测 wrangler 命令
set WRANGLER_CMD=wrangler
where wrangler >nul 2>&1
if %errorlevel% neq 0 (
    echo 提示: 未检测到全局 wrangler，尝试使用 npx
    set WRANGLER_CMD=npx wrangler
    
    REM 检查 npx 是否可用
    where npx >nul 2>&1
    if %errorlevel% neq 0 (
        echo 错误: 未找到 wrangler 和 npx
        echo.
        echo 请先安装 Cloudflare Wrangler CLI:
        echo.
        echo 方法1: 使用 npm 全局安装
        echo    npm install -g wrangler
        echo.
        echo 方法2: 使用 npx
        echo    npx wrangler
        echo.
        echo 注意: 如果刚安装 wrangler，请重启终端后再运行
        echo.
        pause
        exit /b 1
    )
)

where npm >nul 2>&1
if %errorlevel% neq 0 (
    echo 错误: 未找到 npm
    echo.
    echo 请先安装 Node.js:
    echo.
    echo 下载地址: https://nodejs.org/
    echo 推荐下载 LTS 长期支持版本
    echo.
    pause
    exit /b 1
)

echo 步骤1: 部署前端
echo.

set FRONTEND_DEPLOYED=0

if not exist "frontend" (
    echo 未检测到 frontend 目录，跳过前端部署
    echo.
    goto deploy_workers
)

REM 询问是否部署前端
set /p SKIP_FRONTEND="是否跳过前端部署? (y/n，默认 n): "
if /i "!SKIP_FRONTEND!"=="y" (
    echo 跳过前端部署
    goto deploy_workers
)

set FRONTEND_DEPLOYED=1

cd frontend
if not exist "package.json" (
    echo 警告: 未找到 frontend/package.json
    cd ..
    goto deploy_workers
)

REM 检查前端配置（如果配置向导中没有创建）
if not exist ".env.local" (
    if not defined DEPLOY_FRONTEND_FLAG (
        echo ================================
        echo 配置前端环境变量
        echo ================================
        echo.
        
        set /p FRONTEND_WORKER_SUBDOMAIN="请输入 Workers 子域名 (例如: miss): "
        set /p FRONTEND_TURNSTILE_KEY="请输入 Turnstile Site Key: "
        
        if not "!FRONTEND_WORKER_SUBDOMAIN!"=="" (
            if "!FRONTEND_TURNSTILE_KEY!"=="" (
                echo 错误: Turnstile Site Key 不能为空
                cd ..
                pause
                exit /b 1
            )
            echo 创建 .env.local...
            (
                echo NEXT_PUBLIC_API_URL=https://sxbot-bot.!FRONTEND_WORKER_SUBDOMAIN!.workers.dev
                echo NEXT_PUBLIC_TURNSTILE_SITE_KEY=!FRONTEND_TURNSTILE_KEY!
            ) > .env.local
            echo 配置完成
            echo.
        )
    )
)

if not exist "node_modules" (
    echo 安装前端依赖...
    call npm install
    if !errorlevel! neq 0 (
        echo 错误: npm install 失败
        cd ..
        pause
        exit /b 1
    )
)

echo 构建 Next.js...
call npm run build
if !errorlevel! neq 0 (
    echo 错误: 构建失败
    cd ..
    pause
    exit /b 1
)

REM 确保环境变量存在（从配置向导或现有文件读取）
if exist ".env.local" (
    for /f "tokens=1,2 delims==" %%a in ('findstr "NEXT_PUBLIC_TURNSTILE_SITE_KEY" .env.local') do (
        set TURNSTILE_SITE_KEY_VALUE=%%b
    )
)

echo 部署到 Cloudflare Pages...
echo 正在从 Cloudflare 获取已有项目...

REM 从 Cloudflare 拉取现有项目，查找包含 sxbot 或 sx-app 的项目
set PAGES_PROJECT_NAME=
call !WRANGLER_CMD! pages project list > temp_pages_list.txt 2>&1

REM 解析表格第一列（Project Name），查找项目名
for /f "tokens=1 delims=│" %%a in ('findstr /C:"sxbot" /C:"sx-app" temp_pages_list.txt') do (
    set TEMP_NAME=%%a
    REM 去除前后空格和表格符号
    set TEMP_NAME=!TEMP_NAME:├=!
    set TEMP_NAME=!TEMP_NAME:│=!
    for /f "tokens=*" %%b in ("!TEMP_NAME!") do (
        set CLEAN_NAME=%%b
        REM 检查是否是有效的项目名（不包含 "Project" 等表头文字）
        echo !CLEAN_NAME! | findstr /V /C:"Project" /C:"─" /C:"┌" /C:"└" /C:"Name" >nul
        if !errorlevel! equ 0 (
            if not "!CLEAN_NAME!"=="" (
                set PAGES_PROJECT_NAME=!CLEAN_NAME!
                goto found_project
            )
        )
    )
)
:found_project

del temp_pages_list.txt 2>nul

if defined PAGES_PROJECT_NAME (
    REM 去除所有空格
    set PAGES_PROJECT_NAME=!PAGES_PROJECT_NAME: =!
    echo 找到已有项目: !PAGES_PROJECT_NAME!
) else (
    REM 如果没有找到，创建新项目
    set RANDOM_SUFFIX=%RANDOM%
    set PAGES_PROJECT_NAME=!RANDOM_SUFFIX!-sx-app
    echo 创建新项目: !PAGES_PROJECT_NAME!
)

echo.
call !WRANGLER_CMD! pages deploy out --project-name=!PAGES_PROJECT_NAME! --branch=main
if !errorlevel! neq 0 (
    echo 错误: 部署失败
    cd ..
    pause
    exit /b 1
)

echo 成功: 前端部署完成
REM 去除项目名中的所有空格
set PAGES_PROJECT_NAME=!PAGES_PROJECT_NAME: =!
set PAGES_URL=https://!PAGES_PROJECT_NAME!.pages.dev
echo URL: !PAGES_URL!
echo    项目名: !PAGES_PROJECT_NAME!
echo.

REM 设置 Cloudflare Pages 环境变量
echo 正在设置 Pages 环境变量...
if defined TURNSTILE_SITE_KEY_VALUE (
    call !WRANGLER_CMD! pages project get !PAGES_PROJECT_NAME! >nul 2>&1
    if !errorlevel! equ 0 (
        echo 设置 NEXT_PUBLIC_TURNSTILE_SITE_KEY...
        call !WRANGLER_CMD! pages project env set NEXT_PUBLIC_TURNSTILE_SITE_KEY "!TURNSTILE_SITE_KEY_VALUE!" --project-name=!PAGES_PROJECT_NAME!
        
        REM 获取 Workers URL 用于设置 API_URL（暂时使用占位符，将在 Workers 部署后更新）
        echo 设置 NEXT_PUBLIC_API_URL...
        call !WRANGLER_CMD! pages project env set NEXT_PUBLIC_API_URL "https://sxbot-bot.workers.dev" --project-name=!PAGES_PROJECT_NAME!
        
        echo Pages 环境变量设置完成
        echo.
        echo ⚠️ 环境变量已更新，需要重新部署以生效...
        echo 正在触发重新部署...
        call !WRANGLER_CMD! pages deploy out --project-name=!PAGES_PROJECT_NAME! --branch=main
        echo 前端已使用新环境变量重新部署
    ) else (
        echo 警告: 无法获取 Pages 项目信息，跳过环境变量设置
    )
) else (
    echo 警告: 未找到 Turnstile Site Key，跳过环境变量设置
)
echo.

cd ..

:deploy_workers
echo 步骤2: 部署 Workers
echo.

REM 如果前端被跳过且没有项目名，尝试从 Cloudflare 获取
if not defined PAGES_PROJECT_NAME (
    echo 正在获取 Pages 项目信息...
    call !WRANGLER_CMD! pages project list > temp_pages_list.txt 2>&1
    for /f "tokens=1 delims=│" %%a in ('findstr /C:"sxbot" /C:"sx-app" temp_pages_list.txt') do (
        set TEMP_NAME=%%a
        set TEMP_NAME=!TEMP_NAME:├=!
        set TEMP_NAME=!TEMP_NAME:│=!
        for /f "tokens=*" %%b in ("!TEMP_NAME!") do (
            set CLEAN_NAME=%%b
            echo !CLEAN_NAME! | findstr /V /C:"Project" /C:"─" /C:"┌" /C:"└" /C:"Name" >nul
            if !errorlevel! equ 0 (
                if not "!CLEAN_NAME!"=="" (
                    set PAGES_PROJECT_NAME=!CLEAN_NAME!
                    goto found_pages_project
                )
            )
        )
    )
    :found_pages_project
    del temp_pages_list.txt 2>nul
    
    if defined PAGES_PROJECT_NAME (
        REM 去除所有空格
        set PAGES_PROJECT_NAME=!PAGES_PROJECT_NAME: =!
        echo 找到 Pages 项目: !PAGES_PROJECT_NAME!
        echo.
    )
)

cd workers
if not exist "package.json" (
    echo 警告: 未找到 workers/package.json
    cd ..
    goto finish
)

REM 检查配置状态
echo ================================
echo 检查配置...
echo ================================
echo.

set CONFIG_NEEDED=0

REM 检查 ADMIN_IDS
findstr /C:"123456789" wrangler.toml >nul
if !errorlevel! equ 0 (
    echo 检测到默认管理员 ID，需要配置
    set CONFIG_NEEDED=1
)

REM 检查是否已设置 BOT_TOKEN secret
call !WRANGLER_CMD! secret list 2>nul | findstr /C:"BOT_TOKEN" >nul
if !errorlevel! neq 0 (
    echo 检测到未设置 Bot Token，需要配置
    set CONFIG_NEEDED=1
)

REM 检查是否已设置 TURNSTILE_SECRET
call !WRANGLER_CMD! secret list 2>nul | findstr /C:"TURNSTILE_SECRET" >nul
if !errorlevel! neq 0 (
    echo 检测到未设置 Turnstile Secret，需要配置
    set CONFIG_NEEDED=1
)

if !CONFIG_NEEDED! equ 1 (
    echo ================================
    echo 首次部署配置向导
    echo ================================
    echo.
) else (
    echo ✅ 配置检查通过，跳过配置向导
    echo.
    goto skip_config
)

if !CONFIG_NEEDED! equ 1 (
    
    REM 输入 Telegram Bot Token
    echo [1/5] Telegram Bot 配置
    set /p INPUT_BOT_TOKEN="请输入 Telegram Bot Token: "
    if "!INPUT_BOT_TOKEN!"=="" (
        echo 错误: Bot Token 不能为空
        cd ..
        pause
        exit /b 1
    )
    echo.
    
    REM 输入管理员 Telegram ID
    echo [2/5] 管理员配置
    set /p INPUT_ADMIN_ID="请输入管理员 Telegram 用户 ID: "
    if "!INPUT_ADMIN_ID!"=="" (
        echo 错误: 管理员 ID 不能为空
        cd ..
        pause
        exit /b 1
    )
    echo.
    
    REM 注意：Workers 子域名由 Cloudflare 账户决定，无需输入
    echo [3/5] Workers 配置
    echo Workers 将自动部署，子域名由 Cloudflare 账户决定
    echo.
    
    REM Turnstile 配置 (必填)
    echo [4/5] Turnstile 配置 (必填，用于防机器人)
    echo.
    echo 请先在 Cloudflare Dashboard 创建 Turnstile 站点:
    echo.
    echo 1. 访问: https://dash.cloudflare.com/?to=/:account/turnstile
    echo 2. 点击 "Add Site" 创建站点
    REM 使用 PAGES_PROJECT_NAME 构建域名，去除所有空格
    if defined PAGES_PROJECT_NAME (
        set CLEAN_PROJECT_NAME=!PAGES_PROJECT_NAME: =!
        echo 3. 在 Domains 字段中填写: !CLEAN_PROJECT_NAME!.pages.dev
    ) else (
        echo 3. 在 Domains 字段中填写你的 Pages 域名
    )
    echo 4. Widget Mode 选择: Managed
    echo 5. 复制 Site Key 和 Secret Key
    echo.
    set /p INPUT_TURNSTILE_SECRET="请输入 Turnstile Secret Key: "
    if "!INPUT_TURNSTILE_SECRET!"=="" (
        echo 错误: Turnstile Secret Key 不能为空
        cd ..
        pause
        exit /b 1
    )
    set /p INPUT_TURNSTILE_SITE="请输入 Turnstile Site Key: "
    if "!INPUT_TURNSTILE_SITE!"=="" (
        echo 错误: Turnstile Site Key 不能为空
        cd ..
        pause
        exit /b 1
    )
    echo.
    
    REM 前端项目配置
    echo [5/5] 前端项目配置
    
    REM 设置 Pages 域名（用于 Turnstile 配置提示）
    if defined PAGES_PROJECT_NAME (
        REM 清理空格
        set PAGES_PROJECT_NAME=!PAGES_PROJECT_NAME: =!
        set PAGES_DOMAIN=!PAGES_PROJECT_NAME!.pages.dev
        echo 前端域名: !PAGES_DOMAIN!
    ) else (
        echo 警告: 未检测到前端项目名，请手动填写域名
        set PAGES_DOMAIN=请查看前端部署输出的域名
    )
    
    set DEPLOY_FRONTEND_FLAG=0
    if defined FRONTEND_DEPLOYED (
        if !FRONTEND_DEPLOYED! equ 1 (
            echo 前端已在步骤1部署
            set DEPLOY_FRONTEND_FLAG=0
        )
    ) else (
        if exist "..\frontend\package.json" (
            set /p CONFIRM_FRONTEND="检测到 frontend 项目，是否需要配置并部署? (y/n，默认 n): "
            if /i "!CONFIRM_FRONTEND!"=="y" (
                set DEPLOY_FRONTEND_FLAG=1
            )
        )
    )
    echo.
    
    echo ================================
    echo 正在应用配置...
    echo ================================
    echo.
    
    REM 更新 ADMIN_IDS
    echo [1/4] 更新管理员 ID...
    powershell -Command "(Get-Content wrangler.toml) -replace 'ADMIN_IDS = \"123456789\"', 'ADMIN_IDS = \"!INPUT_ADMIN_ID!\"' | Set-Content wrangler.toml"
    
    REM 更新 MINIAPP_URL（如果有 Pages 项目名）
    if defined PAGES_PROJECT_NAME (
        echo 更新前端 URL...
        powershell -Command "(Get-Content wrangler.toml) -replace 'MINIAPP_URL = \"https://.*\.pages\.dev\"', 'MINIAPP_URL = \"https://!PAGES_PROJECT_NAME!.pages.dev\"' | Set-Content wrangler.toml"
    )
    
    REM 设置 BOT_TOKEN secret
    echo [2/4] 设置 Bot Token...
    powershell -Command "$env:INPUT_BOT_TOKEN='!INPUT_BOT_TOKEN!'; Write-Output $env:INPUT_BOT_TOKEN | !WRANGLER_CMD! secret put BOT_TOKEN"
    
    REM 设置 TURNSTILE_SECRET
    echo [3/4] 设置 Turnstile Secret...
    powershell -Command "$env:INPUT_TURNSTILE='!INPUT_TURNSTILE_SECRET!'; Write-Output $env:INPUT_TURNSTILE | !WRANGLER_CMD! secret put TURNSTILE_SECRET"
    
    REM 创建前端配置文件
    if !DEPLOY_FRONTEND_FLAG! equ 1 (
        echo [4/4] 配置前端环境变量...
        cd ..
        if not exist "frontend" mkdir frontend
        (
            echo NEXT_PUBLIC_API_URL=https://sxbot-bot.workers.dev
            echo NEXT_PUBLIC_TURNSTILE_SITE_KEY=!INPUT_TURNSTILE_SITE!
        ) > frontend\.env.local
        echo 前端环境变量已创建
        cd workers
    ) else (
        echo [4/4] 创建前端环境变量...
        cd ..
        if exist "frontend" (
            (
                echo NEXT_PUBLIC_API_URL=https://sxbot-bot.workers.dev
                echo NEXT_PUBLIC_TURNSTILE_SITE_KEY=!INPUT_TURNSTILE_SITE!
            ) > frontend\.env.local
            echo 前端环境变量已创建（Workers URL 将在部署后自动更新）
        )
        cd workers
    )
    
    echo.
    echo 配置完成
    echo.
)

:skip_config
if not exist "node_modules" (
    echo 安装 Workers 依赖...
    call npm install
    if !errorlevel! neq 0 (
        echo 错误: npm install 失败
        cd ..
        pause
        exit /b 1
    )
)

REM 检查是否需要创建 KV Namespace
findstr /C:"YOUR_KV_NAMESPACE_ID" wrangler.toml >nul
if !errorlevel! equ 0 (
    echo 检测到未配置 KV Namespace，正在创建...
    echo.
    for /f "tokens=*" %%i in ('call !WRANGLER_CMD! kv namespace create KV ^| findstr /C:"id = "') do (
        set KV_OUTPUT=%%i
    )
    
    REM 提取 KV ID
    for /f "tokens=3 delims= " %%a in ("!KV_OUTPUT!") do set KV_ID=%%a
    set KV_ID=!KV_ID:"=!
    
    if "!KV_ID!"=="" (
        echo 错误: 无法创建 KV Namespace
        cd ..
        pause
        exit /b 1
    )
    
    echo KV Namespace 创建成功，ID: !KV_ID!
    echo 正在自动更新 wrangler.toml...
    
    REM 替换配置文件中的 KV ID
    powershell -Command "(Get-Content wrangler.toml) -replace 'YOUR_KV_NAMESPACE_ID', '!KV_ID!' | Set-Content wrangler.toml"
    
    echo 配置已更新
    echo.
)

echo 部署 Workers...

REM 部署并保存输出到临时文件
call !WRANGLER_CMD! deploy > deploy_output.tmp 2>&1
type deploy_output.tmp

REM 从输出中提取 Workers URL（查找 .workers.dev 结尾的 URL）
set ACTUAL_WORKERS_URL=
for /f "tokens=*" %%i in ('findstr "workers.dev" deploy_output.tmp') do (
    set LINE=%%i
    REM 去除前后空格，提取 URL
    for /f "tokens=*" %%a in ("!LINE!") do set ACTUAL_WORKERS_URL=%%a
)

REM 删除临时文件
del deploy_output.tmp

REM 如果提取到了 URL，去除可能的前后空格
if defined ACTUAL_WORKERS_URL (
    REM 使用 PowerShell 去除空格并验证
    for /f "delims=" %%a in ('powershell -Command "('!ACTUAL_WORKERS_URL!').Trim()"') do set ACTUAL_WORKERS_URL=%%a
)

if "!ACTUAL_WORKERS_URL!"=="" (
    echo 警告: 无法自动获取 Workers URL
    set ACTUAL_WORKERS_URL=未知
)

echo 成功: Workers 部署完成
echo Workers URL: !ACTUAL_WORKERS_URL!
echo.

REM 如果前端存在，更新配置文件
if exist "..\frontend\.env.local" (
    if not "!ACTUAL_WORKERS_URL!"=="未知" (
        echo 正在更新前端配置...
        powershell -Command "(Get-Content ..\frontend\.env.local) -replace 'NEXT_PUBLIC_API_URL=.*', 'NEXT_PUBLIC_API_URL=!ACTUAL_WORKERS_URL!' | Set-Content ..\frontend\.env.local"
        echo 前端本地配置已更新
        echo.
        echo ⚠️ Workers URL 已更新，需要重新构建并部署前端:
        echo    cd frontend
        echo    npm run build
        echo    !WRANGLER_CMD! pages deploy out --project-name=!PAGES_PROJECT_NAME! --branch=main
        echo.
    )
)

cd ..

:finish
echo ================================
echo 部署完成
echo ================================
echo.

echo 步骤3: 设置 Webhook
echo.

REM 如果有实际的 Workers URL，使用它
if defined INPUT_BOT_TOKEN (
    if defined ACTUAL_WORKERS_URL (
        if not "!ACTUAL_WORKERS_URL!"=="未知" (
            echo 自动设置 Webhook...
            set WEBHOOK_URL=!ACTUAL_WORKERS_URL!/webhook
            echo URL: !WEBHOOK_URL!
            
            REM 使用 PowerShell 设置 Webhook
            powershell -Command "try { $result = Invoke-RestMethod -Uri 'https://api.telegram.org/bot!INPUT_BOT_TOKEN!/setWebhook' -Method Post -ContentType 'application/json' -Body '{\"url\": \"!WEBHOOK_URL!\"}'; if ($result.ok) { Write-Host 'Webhook 设置成功' } else { Write-Host 'Webhook 设置失败:' $result.description } } catch { Write-Host 'Webhook 设置失败' }"
            
            echo.
            echo.
            goto show_summary
        )
    )
)

REM 否则询问用户手动输入
set /p MANUAL_BOT_TOKEN="输入 Bot Token (回车跳过): "

if "!MANUAL_BOT_TOKEN!"=="" (
    echo 已跳过 Webhook 设置
    goto show_summary
)

set /p MANUAL_WEBHOOK_URL="输入完整的 Workers URL (例如: https://sxbot-bot.xxx.workers.dev): "

if "!MANUAL_WEBHOOK_URL!"=="" (
    echo 错误: 需要 Workers URL
    goto show_summary
)

set WEBHOOK_URL=!MANUAL_WEBHOOK_URL!/webhook

echo 设置 Webhook: !WEBHOOK_URL!

REM 使用 PowerShell 的 Invoke-RestMethod 替代 curl
powershell -Command "try { $result = Invoke-RestMethod -Uri 'https://api.telegram.org/bot!MANUAL_BOT_TOKEN!/setWebhook' -Method Post -ContentType 'application/json' -Body '{\"url\": \"!WEBHOOK_URL!\"}'; if ($result.ok) { Write-Host 'Webhook 设置成功' } else { Write-Host 'Webhook 设置失败' } } catch { Write-Host 'Webhook 设置失败' }"

echo.

:show_summary
REM 确保项目名没有空格（用于最终显示）
if defined PAGES_PROJECT_NAME (
    set PAGES_PROJECT_NAME=!PAGES_PROJECT_NAME: =!
)
echo ================================
echo 部署总结
echo ================================
echo.
echo ✅ Workers 已部署并运行
if defined ACTUAL_WORKERS_URL (
    if not "!ACTUAL_WORKERS_URL!"=="未知" (
        echo    Workers URL: !ACTUAL_WORKERS_URL!
    )
)
echo.
echo ✅ 前端已部署
if defined PAGES_PROJECT_NAME (
    echo    Pages URL: https://!PAGES_PROJECT_NAME!.pages.dev
) else (
    echo    Pages URL: https://xxxxx-sx-app.pages.dev
)
echo.
echo ✅ Turnstile 验证已配置
if defined PAGES_PROJECT_NAME (
    echo    站点域名: !PAGES_PROJECT_NAME!.pages.dev
) else (
    echo    站点域名: xxxxx-sx-app.pages.dev
)
echo.
echo 💡 重要提示:
echo.
echo 1. 确保 Turnstile 站点域名设置正确
echo    访问: https://dash.cloudflare.com/?to=/:account/turnstile
if defined PAGES_PROJECT_NAME (
    echo    Domains 字段应填写: !PAGES_PROJECT_NAME!.pages.dev
) else (
    echo    Domains 字段应填写: 你的Pages域名
)
echo    (不要加 https:// 或其他前缀)
echo.
echo 2. 如需更新配置，可运行:
echo    cd workers
echo    !WRANGLER_CMD! secret put BOT_TOKEN
echo    !WRANGLER_CMD! secret put TURNSTILE_SECRET
echo.
echo 3. 查看 Bot 日志:
echo    cd workers
echo    !WRANGLER_CMD! tail
echo.
pause
