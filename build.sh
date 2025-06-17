set -e
echo "--- 开始执行 build.sh 脚本 ---"
# --- 1. 变量定义与配置 ---
# 这里硬编码了 AList 二进制文件的下载 URL。
# 请务必确保这个 URL 是最新的、有效的，并且指向的是一个可下载的 .tar.gz 文件。
# 如果未来 AList 的下载链接有变化，您需要手动更新此变量。
ALIST_DOWNLOAD_URL="https://github.com/AlliotTech/openalist/releases/download/beta/alist-linux-arm64.tar.gz"

# 关于 LATEST_VERSION：
# 你的原始脚本在获取 LATEST_VERSION 时遇到了问题。
# 这里我们建议通过 GitHub Actions workflow 传递标签名作为版本号，这是最可靠的方式。
# 如果你选择这样做，请确保修改你的 release.yml workflow，在调用 build.sh 时传递参数：
# 例如：bash build.sh ${{ github.ref_name }}
# 脚本会接收这个参数作为第一个位置参数 $1
if [ -n "$1" ]; then
    # 如果通过参数传入了版本号（即 Git Tag），则使用它。
    # 我们通常会去除标签前的 'v' (例如 'v3.45.0' 变为 '3.45.0')
    LATEST_VERSION=$(echo "$1" | sed 's/^v//')
else
    # 如果没有通过参数传入版本号，则使用一个默认值或尝试从下载 URL 推断。
    # 注意：从URL推断可能不总是可靠，手动指定或通过参数传入更佳。
    LATEST_VERSION="unknown_version"
    echo "警告：未从参数中获取到版本号，使用默认值：${LATEST_VERSION}"
fi

echo "下载 AList 的 URL: ${ALIST_DOWNLOAD_URL}"
echo "当前版本号 (用于命名和 module.prop): ${LATEST_VERSION}"


# --- 2. 安装必要的系统依赖 ---
echo "--- 更新软件包列表并安装依赖项 (upx-ucl, git, curl, unzip) ---"
sudo apt-get update || { echo "错误：apt 列表更新失败"; exit 1; }
# upx-ucl 是 upx 在 Ubuntu 上的软件包名称
sudo apt-get install upx-ucl git curl unzip -y || { echo "错误：依赖安装失败"; exit 1; }
echo "依赖项安装完成。"


# --- 3. 创建临时目录并进入 ---
echo "--- 创建临时构建目录 ---"
TMP_DIR="alist_temp_build"
mkdir -p "$TMP_DIR" || { echo "错误：无法创建临时目录 ${TMP_DIR}"; exit 1; }
cd "$TMP_DIR" || { echo "错误：无法进入临时目录 ${TMP_DIR}"; exit 1; }
echo "已进入临时目录: $(pwd)"


# --- 4. 下载 AList .tar.gz 文件 ---
ALIST_TAR_GZ_FILE="alist-binary.tar.gz"
echo "--- 正在从 ${ALIST_DOWNLOAD_URL} 下载 AList 二进制文件 ---"
# -s: 静默模式，不显示进度条或错误信息
# -L: 跟随 HTTP 重定向，这在下载链接可能经过多次跳转时非常有用
# --fail: 任何 HTTP 错误（如 404 Not Found）都会导致 curl 以非零状态码退出，从而使脚本失败
# -o: 指定输出文件名
curl -sL --fail -o "${ALIST_TAR_GZ_FILE}" "${ALIST_DOWNLOAD_URL}"
if [ $? -ne 0 ]; then
    echo "错误：从 ${ALIST_DOWNLOAD_URL} 下载 AList 归档文件失败。"
    echo "请检查 URL 是否正确且网络连接正常。"
    exit 1
fi
echo "AList 二进制文件已下载到 ${ALIST_TAR_GZ_FILE}。"

# --- 5. 验证并解压 .tar.gz 文件 ---
echo "--- 正在验证并解压 AList 归档文件 ---"
# 首先，验证下载的文件是否是有效的 tar 归档。
if ! tar -tf "${ALIST_TAR_GZ_FILE}" &>/dev/null; then
    echo "错误：下载的文件 '${ALIST_TAR_GZ_FILE}' 不是一个有效的 tar 归档文件或已损坏。"
    exit 1
fi

# 解压文件。根据之前的错误，alist 可执行文件会直接解压到当前目录 (temp/)。
# 移除 -v，因为有时会导致不必要的日志。
tar -zxvf "${ALIST_TAR_GZ_FILE}"
echo "AList 归档文件已解压。"

# 查找解压后的 alist 可执行文件路径。
# 根据最新的错误信息，alist 可执行文件在解压后就直接在当前目录 (temp/) 下。
# 移除动态获取 EXTRACTED_DIR 的逻辑，直接指定 alist 文件的路径。
ALIST_BIN_SOURCE_PATH="./alist" # <--- 核心修改点：直接指向当前目录下的 'alist' 文件

# 检查 alist 二进制文件是否存在于预期的路径
if [ ! -f "${ALIST_BIN_SOURCE_PATH}" ]; then
    echo "错误：在解压后，未在预期路径 ${ALIST_BIN_SOURCE_PATH} 找到 AList 可执行文件。"
    echo "当前目录 ($(pwd)) 的内容如下：" # 打印当前目录内容以帮助调试
    ls -l . # 列出当前目录的内容
    exit 1
fi
echo "已找到 AList 可执行文件在: ${ALIST_BIN_SOURCE_PATH}"


# --- 6. 使用 UPX 压缩 Alist 二进制文件 ---
echo "--- 正在使用 UPX 压缩 AList 二进制文件 ---"
# 定义压缩后的新文件名
COMPRESSED_ALIST_NAME="alist_${LATEST_VERSION}_aarch64_upx"
upx -9 "${ALIST_BIN_SOURCE_PATH}" -o "${COMPRESSED_ALIST_NAME}"
if [ $? -ne 0 ]; then
    echo "错误：UPX 压缩 ${ALIST_BIN_SOURCE_PATH} 失败。"
    exit 1
fi
echo "AList 二进制文件已压缩为: ${COMPRESSED_ALIST_NAME}"


# --- 7. 将压缩后的 Alist 移动到项目根目录的 bin/alist ---
# 返回到项目根目录，以便后续操作（如打包）在正确的上下文进行
cd ..
echo "已返回到项目根目录: $(pwd)"

# 确保 bin 目录存在。如果不存在，则创建它。
mkdir -p bin || { echo "错误：无法创建 bin 目录"; exit 1; }

# 将压缩后的 Alist 文件从临时目录移动到 bin/alist
echo "--- 将压缩后的 AList 移动到 bin/alist ---"
mv "${TMP_DIR}/${COMPRESSED_ALIST_NAME}" bin/alist
if [ $? -ne 0 ]; then
    echo "错误：无法将 ${TMP_DIR}/${COMPRESSED_ALIST_NAME} 移动到 bin/alist。"
    exit 1
fi
echo "压缩后的 AList 已成功移动到 bin/alist。"


# --- 8. 清理临时目录 ---
echo "--- 清理临时构建目录 ---"
rm -rf "$TMP_DIR"
echo "临时目录 ${TMP_DIR} 已删除。"


# --- 9. 更新 module.prop 中的版本号 (可选，根据你的需求) ---
echo "--- 正在更新 module.prop 文件中的版本号 ---"
# 获取 module.prop 中当前的 version 值
ALIST_VERSION_PROP_OLD=$(grep -oP '^version=\K\S+' module.prop)
# 使用 sed 命令更新 version 行。
# 这里假设 module.prop 中的 version 字段需要以 'v' 开头，
# 而 LATEST_VERSION 已经移除了 'v' (例如 '3.45.0')
sed -i "s/^version=$ALIST_VERSION_PROP_OLD$/version=v$LATEST_VERSION/" module.prop
echo "module.prop 已更新：旧版本为 ${ALIST_VERSION_PROP_OLD}，新版本为 v${LATEST_VERSION}。"


# --- 10. 打包所有相关文件到 Alist-Server.zip ---
echo "--- 正在创建 Alist-Server.zip ---"
# `zip -r Alist-Server.zip .` 表示将当前目录下的所有内容递归打包到 Alist-Server.zip
# `-x` 参数用于排除不需要打包的文件或目录。
# 请仔细检查并确保排除规则是正确的，以避免打包不必要的文件或泄露敏感信息。
# 示例排除：build.sh 脚本本身, update.json (如果存在且不需要), .github/ 目录及其所有内容，临时目录等
zip -r Alist-Server.zip . \
    -x "build.sh" \
    -x "update.json" \
    -x ".github/*" \
    -x "__pycache__/*" \
    -x "*.pyc" \
    -x "*.DS_Store" \
    -x "*.git*" \
    -x "*${TMP_DIR}*" # 排除所有临时构建目录相关的文件或目录
    
if [ $? -ne 0 ]; then
    echo "错误：创建 Alist-Server.zip 失败。"
    exit 1
fi
echo "Alist-Server.zip 已成功创建。"

echo "--- 脚本执行完毕 ---"