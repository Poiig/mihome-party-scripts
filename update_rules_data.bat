@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ===== 常量定义 =====
:: 获取当前日期
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set "CURRENT_DATE=%datetime:~0,4%-%datetime:~4,2%-%datetime:~6,2%"

:: 文件路径设置
set "SCRIPT_DIR=%~dp0"
set "LOG_DIR=%SCRIPT_DIR%log"
set "LOG_FILE=%LOG_DIR%\%CURRENT_DATE%.log"
set "TEMP_DIR=%SCRIPT_DIR%temp"
set "CONFIG_FILE=%SCRIPT_DIR%config.ini"

:: 创建必要的目录
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

:: 文件名常量
set "GEOIP_DAT=geoip.dat"
set "GEOSITE_DAT=geosite.dat"
set "GEOIP_METADB=geoip.metadb"
set "ASN_MMDB=ASN.mmdb"
set "COUNTRY_MMDB=country.mmdb"

:: ===== 初始化 =====
:: 记录日志
call :log "====== 开始更新规则文件 ======"

:: 目标目录（固定使用环境变量）
set "MIHOMO_BASE=%APPDATA%\mihomo-party"
set "TEST_DIR=%MIHOMO_BASE%\test"
set "WORK_DIR=%MIHOMO_BASE%\work"

call :log "目标目录: TEST_DIR=%TEST_DIR%, WORK_DIR=%WORK_DIR%"

:: 检查配置文件是否存在，不存在则创建默认配置
if not exist "%CONFIG_FILE%" (
    call :create_default_config
)

:: 读取配置文件中的URL
call :read_config

:: ===== 主程序 =====
:: 下载文件
call :log "开始下载文件"
set "DOWNLOAD_SUCCESS=true"

:: 下载geoip.dat
call :download_file "%GEOIP_URL%" "%TEMP_DIR%\%GEOIP_DAT%"
if !errorlevel! neq 0 set "DOWNLOAD_SUCCESS=false"

:: 下载geosite.dat
call :download_file "%GEOSITE_URL%" "%TEMP_DIR%\%GEOSITE_DAT%"
if !errorlevel! neq 0 set "DOWNLOAD_SUCCESS=false"

:: 下载geoip.metadb
call :download_file "%GEOIPDB_URL%" "%TEMP_DIR%\%GEOIP_METADB%"
if !errorlevel! neq 0 set "DOWNLOAD_SUCCESS=false"

:: 下载ASN.mmdb
call :download_file "%ASNDB_URL%" "%TEMP_DIR%\%ASN_MMDB%"
if !errorlevel! neq 0 set "DOWNLOAD_SUCCESS=false"

:: 下载country.mmdb
call :download_file "%COUNTRY_URL%" "%TEMP_DIR%\%COUNTRY_MMDB%"
if !errorlevel! neq 0 set "DOWNLOAD_SUCCESS=false"

:: 如果有下载失败，则终止程序
if "%DOWNLOAD_SUCCESS%"=="false" (
    call :log "部分文件下载失败，更新终止"
    echo 下载失败，请检查网络连接或URL配置。详情请查看日志。
    goto :end
)

:: 更新test目录
call :update_directory "%TEST_DIR%"

:: 更新work目录及其子目录
call :update_directory "%WORK_DIR%"
call :update_subdirectories "%WORK_DIR%"

call :log "====== 规则文件更新完成 ======"
echo 规则文件更新完成！请查看日志了解详细信息：%LOG_FILE%

:end
pause
exit /b 0

:: ===== 函数定义 =====

:log
echo [%date% %time%] %~1 >> "%LOG_FILE%"
echo %~1
exit /b 0

:create_default_config
(
    echo [URLS]
    echo GEOIP_URL=https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat
    echo GEOSITE_URL=https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat
    echo GEOIPDB_URL=https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb
    echo ASNDB_URL=https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb
) > "%CONFIG_FILE%"
call :log "创建默认配置文件: %CONFIG_FILE%"
exit /b 0

:read_config
:: 读取URL配置
for /f "usebackq tokens=1,* delims==" %%a in ("%CONFIG_FILE%") do (
    if not "%%a"=="[URLS]" (
        set "%%a=%%b"
    )
)
call :log "配置文件加载完成"
exit /b 0

:download_file
setlocal
set "URL=%~1"
set "OUTPUT_FILE=%~2"
set "TEMP_FILE=%OUTPUT_FILE%.tmp"
call :log "开始下载: %URL% 到 %OUTPUT_FILE%"

:: 删除可能存在的临时文件
if exist "%TEMP_FILE%" del "%TEMP_FILE%"

:: 方法1: 使用curl
where curl >nul 2>nul
if %errorlevel% equ 0 (
    call :log "尝试使用curl下载..."
    curl -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" -L --silent --connect-timeout 30 --retry 3 "%URL%" -o "%TEMP_FILE%" 2>>"%LOG_FILE%"
    if !errorlevel! equ 0 if exist "%TEMP_FILE%" (
        move /Y "%TEMP_FILE%" "%OUTPUT_FILE%" >nul
        call :log "curl下载成功: %OUTPUT_FILE%"
        exit /b 0
    )
    call :log "curl下载失败，尝试其他方法..."
)

:: 方法2: 使用PowerShell WebClient
call :log "尝试使用PowerShell WebClient下载..."
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference = 'SilentlyContinue'; $wc = New-Object System.Net.WebClient; $wc.Headers.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'); try { $wc.DownloadFile('%URL%', '%TEMP_FILE%'); if(Test-Path '%TEMP_FILE%') { Move-Item -Force '%TEMP_FILE%' '%OUTPUT_FILE%' -ErrorAction Stop; exit 0 } else { Write-Error 'Download failed: File not found'; exit 1 } } catch { Write-Error $_.Exception.Message; exit 1 }" 2>>"%LOG_FILE%"

if %errorlevel% equ 0 if exist "%OUTPUT_FILE%" (
    call :log "WebClient下载成功: %OUTPUT_FILE%"
    exit /b 0
)

:: 方法3: 使用BITS传输
call :log "尝试使用BITS传输下载..."
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module BitsTransfer; try { Start-BitsTransfer -Source '%URL%' -Destination '%TEMP_FILE%' -TransferType Download -DisplayName 'Downloading' -Priority High -ErrorAction Stop; if(Test-Path '%TEMP_FILE%') { Move-Item -Force '%TEMP_FILE%' '%OUTPUT_FILE%' -ErrorAction Stop; exit 0 } else { Write-Error 'BITS transfer failed: File not found'; exit 1 } } catch { Write-Error $_.Exception.Message; exit 1 }" 2>>"%LOG_FILE%"

if %errorlevel% equ 0 if exist "%OUTPUT_FILE%" (
    call :log "BITS传输下载成功: %OUTPUT_FILE%"
    exit /b 0
)

call :log "所有下载方法均失败: %URL%"
if exist "%TEMP_FILE%" del "%TEMP_FILE%"
exit /b 1

:update_directory
setlocal
set "TARGET_DIR=%~1"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
call :log "开始更新目录: %TARGET_DIR%"

for %%F in ("%GEOIP_DAT%" "%GEOSITE_DAT%" "%GEOIP_METADB%" "%ASN_MMDB%" "%COUNTRY_MMDB%") do (
    copy /Y "%TEMP_DIR%\%%~F" "%TARGET_DIR%\%%~F" >nul
    if !errorlevel! equ 0 (
        call :log "文件已复制到: %TARGET_DIR%\%%~F"
    ) else (
        call :log "复制文件失败: %TEMP_DIR%\%%~F -> %TARGET_DIR%\%%~F"
    )
)
exit /b 0

:update_subdirectories
setlocal
set "PARENT_DIR=%~1"
call :log "开始更新子目录"

for /d %%D in ("%PARENT_DIR%\*") do (
    call :update_directory "%%D"
)
exit /b 0 