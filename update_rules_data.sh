#!/bin/bash

# ===== 常量定义 =====
# 获取当前日期
CURRENT_DATE=$(date +"%Y-%m-%d")

# 文件路径设置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/log"
LOG_FILE="${LOG_DIR}/${CURRENT_DATE}.log"
TEMP_DIR="${SCRIPT_DIR}/temp"
CONFIG_FILE="${SCRIPT_DIR}/config.ini"

# 创建必要的目录
mkdir -p "${LOG_DIR}"
mkdir -p "${TEMP_DIR}"

# 文件名常量
GEOIP_DAT="geoip.dat"
GEOSITE_DAT="geosite.dat"
GEOIP_METADB="geoip.metadb"
ASN_MMDB="ASN.mmdb"
COUNTRY_MMDB="country.mmdb"

# ===== 初始化 =====
# 记录日志函数
log() {
	echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log "====== 开始更新规则文件 ======"

# 目标目录（固定使用环境变量）
APP_RESOURCE_DIR="/Applications/Mihome Party.app/Contents/Resources/files"
USER_HOME="$HOME"
MIHOMO_BASE="${USER_HOME}/Library/Application Support/mihomo-party"
TEST_DIR="${MIHOMO_BASE}/test"
WORK_DIR="${MIHOMO_BASE}/work"

log "目标目录: APP_RESOURCE_DIR=${APP_RESOURCE_DIR}, TEST_DIR=${TEST_DIR}, WORK_DIR=${WORK_DIR}"

# 检查配置文件是否存在，不存在则创建默认配置
create_default_config() {
	cat >"${CONFIG_FILE}" <<EOF
[URLS]
GEOIP_URL=https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat
GEOSITE_URL=https://testingcf.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat
GEOIPDB_URL=https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb
ASNDB_URL=https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb
COUNTRY_URL=https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb
EOF
	log "创建默认配置文件: ${CONFIG_FILE}"
}

if [ ! -f "${CONFIG_FILE}" ]; then
	create_default_config
fi

# 读取配置文件中的URL
read_config() {
	# 检查是否是URL行
	if grep -q "\[URLS\]" "${CONFIG_FILE}"; then
		GEOIP_URL=$(grep "GEOIP_URL" "${CONFIG_FILE}" | cut -d'=' -f2)
		GEOSITE_URL=$(grep "GEOSITE_URL" "${CONFIG_FILE}" | cut -d'=' -f2)
		GEOIPDB_URL=$(grep "GEOIPDB_URL" "${CONFIG_FILE}" | cut -d'=' -f2)
		ASNDB_URL=$(grep "ASNDB_URL" "${CONFIG_FILE}" | cut -d'=' -f2)
		COUNTRY_URL=$(grep "COUNTRY_URL" "${CONFIG_FILE}" | cut -d'=' -f2)
	fi
	log "配置文件加载完成"
}

read_config

# ===== 主程序 =====
# 下载文件
log "开始下载文件"
DOWNLOAD_SUCCESS=true

# 下载函数
download_file() {
	local URL="$1"
	local OUTPUT_FILE="$2"
	local TEMP_FILE="${OUTPUT_FILE}.tmp"

	log "开始下载: ${URL} 到 ${OUTPUT_FILE}"

	# 删除可能存在的临时文件
	rm -f "${TEMP_FILE}"

	# 尝试使用curl下载
	log "尝试使用curl下载..."
	if curl -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" -L --silent --connect-timeout 30 --retry 3 "${URL}" -o "${TEMP_FILE}" 2>>"${LOG_FILE}"; then
		if [ -f "${TEMP_FILE}" ]; then
			mv "${TEMP_FILE}" "${OUTPUT_FILE}"
			log "curl下载成功: ${OUTPUT_FILE}"
			return 0
		fi
	fi

	log "下载失败: ${URL}"
	rm -f "${TEMP_FILE}"
	return 1
}

# 下载所有文件
download_file "${GEOIP_URL}" "${TEMP_DIR}/${GEOIP_DAT}" || DOWNLOAD_SUCCESS=false
download_file "${GEOSITE_URL}" "${TEMP_DIR}/${GEOSITE_DAT}" || DOWNLOAD_SUCCESS=false
download_file "${GEOIPDB_URL}" "${TEMP_DIR}/${GEOIP_METADB}" || DOWNLOAD_SUCCESS=false
download_file "${ASNDB_URL}" "${TEMP_DIR}/${ASN_MMDB}" || DOWNLOAD_SUCCESS=false
download_file "${COUNTRY_URL}" "${TEMP_DIR}/${COUNTRY_MMDB}" || DOWNLOAD_SUCCESS=false

# 如果有下载失败，则终止程序
if [ "${DOWNLOAD_SUCCESS}" = "false" ]; then
	log "部分文件下载失败，更新终止"
	echo "下载失败，请检查网络连接或URL配置。详情请查看日志。"
	exit 1
fi

# 首先复制到应用程序资源目录
update_app_resource() {
	local TARGET_DIR="$1"

	# 确保目标目录存在
	mkdir -p "${TARGET_DIR}"
	log "开始更新资源目录: ${TARGET_DIR}"

	# 复制所有文件
	for FILE in "${GEOIP_DAT}" "${GEOSITE_DAT}" "${GEOIP_METADB}" "${ASN_MMDB}" "${COUNTRY_MMDB}"; do
		if cp "${TEMP_DIR}/${FILE}" "${TARGET_DIR}/${FILE}" 2>/dev/null; then
			log "文件已复制到: ${TARGET_DIR}/${FILE}"
		else
			log "复制文件失败: ${TEMP_DIR}/${FILE} -> ${TARGET_DIR}/${FILE}"
			# 尝试使用sudo
			echo "需要管理员权限来复制文件到应用程序目录"
			if sudo cp "${TEMP_DIR}/${FILE}" "${TARGET_DIR}/${FILE}" 2>/dev/null; then
				log "使用sudo成功复制文件到: ${TARGET_DIR}/${FILE}"
			else
				log "即使使用sudo也无法复制文件。请检查权限或目录是否存在"
			fi
		fi
	done
}

# 更新目录函数
update_directory() {
	local TARGET_DIR="$1"

	# 确保目标目录存在
	mkdir -p "${TARGET_DIR}"
	log "开始更新目录: ${TARGET_DIR}"

	# 复制所有文件
	for FILE in "${GEOIP_DAT}" "${GEOSITE_DAT}" "${GEOIP_METADB}" "${ASN_MMDB}" "${COUNTRY_MMDB}"; do
		if cp "${TEMP_DIR}/${FILE}" "${TARGET_DIR}/${FILE}" 2>/dev/null; then
			log "文件已复制到: ${TARGET_DIR}/${FILE}"
		else
			log "复制文件失败: ${TEMP_DIR}/${FILE} -> ${TARGET_DIR}/${FILE}"
		fi
	done
}

# 更新子目录函数
update_subdirectories() {
	local PARENT_DIR="$1"
	log "开始更新子目录: ${PARENT_DIR}"

	# 查找并更新所有子目录
	find "${PARENT_DIR}" -type d -not -path "${PARENT_DIR}" | while read -r DIR; do
		update_directory "${DIR}"
	done
}

# 更新应用程序资源目录
update_app_resource "${APP_RESOURCE_DIR}"

# 更新test目录
update_directory "${TEST_DIR}"

# 更新work目录及其子目录
update_directory "${WORK_DIR}"
update_subdirectories "${WORK_DIR}"

log "====== 规则文件更新完成 ======"
echo "规则文件更新完成！请查看日志了解详细信息：${LOG_FILE}"
