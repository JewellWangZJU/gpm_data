#!/bin/bash

# ========================================================
# 核心配置区
# ========================================================
# 你的存储桶名字 (根据你的截图填写的)
BUCKET_NAME="gpm111223"

# 起始年份：直接从 2001 年开始，因为 2000 年前半年没数据，容易报错
START_YEAR=2001

# 结束年份：自动获取当前年份
END_YEAR=$(date +%Y)

# NASA 数据地址 (V07 版本)
URL_FINAL="https://gpm1.gesdisc.eosdis.nasa.gov/data/GPM_L3/GPM_3IMERGHH.07"
URL_EARLY="https://gpm1.gesdisc.eosdis.nasa.gov/data/GPM_L3/GPM_3IMERGHHE.07"

# Cookie 文件位置
COOKIE_FILE="$HOME/.urs_cookies"
# ========================================================

# 检查 .netrc 是否存在，不存在就不干活
if [ ! -s "$HOME/.netrc" ]; then
    echo "致命错误：找不到 .netrc 文件！程序退出。"
    exit 1
fi

# 定义一个干活的函数 (下载 -> 上传 -> 删除)
run_task() {
    local TYPE=$1   # 数据类型 (Final 或 Early)
    local BASE_URL=$2
    local YEAR=$3

    echo "==================================================="
    echo "正在处理任务: [ $TYPE ] - 年份: $YEAR"
    echo "==================================================="

    # 1. 开始下载
    # 解释 wget 参数：
    # -r: 递归下载 (整个目录)
    # -np: 不往上爬 (只下载当前目录下)
    # -nH --cut-dirs=3: 把多余的网址前缀去掉，只保留年份/日期目录
    # -A: 只接受 HDF5 和 nc4 格式 (重要！拒绝垃圾文件)
    # -R: 拒绝 xml, html 文件

    wget --load-cookies "$COOKIE_FILE" \
         --save-cookies "$COOKIE_FILE" \
         --keep-session-cookies \
         --auth-no-challenge=on \
         -r -np -nH --cut-dirs=3 \
         -e robots=off \
         -A "*.HDF5,*.nc4" \
         -R "*.xml,*.html" \
         "$BASE_URL/$YEAR/"

    # 2. 检查下载是否成功
    # 如果文件夹存在，且里面不为空
    if [ -d "$YEAR" ] && [ "$(ls -A $YEAR)" ]; then
        echo ">>> $YEAR 年下载完成！准备上传到谷歌云存储..."

        # 3. 上传到 Bucket
        # -m 开启多线程上传，速度更快
        gcloud storage cp -r "$YEAR" "gs://$BUCKET_NAME/$TYPE/"

        # 检查上传命令是否成功 (0代表成功)
        if [ $? -eq 0 ]; then
            echo ">>> 上传成功！为了省钱，正在删除本地文件..."
            rm -rf "$YEAR"
        else
            echo "!!! 警告：上传失败！本地文件已保留，请检查网络。"
        fi
    else
        echo "!!! 跳过：$YEAR 年没有下载到任何数据 (可能是还没发布)。"
        # 如果生成了空文件夹，删掉它
        if [ -d "$YEAR" ]; then rm -rf "$YEAR"; fi
    fi
}

# === 主程序开始 ===
for (( year=$START_YEAR; year<=$END_YEAR; year++ ))
do
    # 先下载 Final Run (高质量数据)
    run_task "Final_Run" "$URL_FINAL" "$year"

    # 再下载 Early Run (实时数据)
    run_task "Early_Run" "$URL_EARLY" "$year"

    echo "年份 $year 全部搞定，休息 3 秒..."
    sleep 3
done

echo "恭喜！所有年份的数据都下载完了！"
