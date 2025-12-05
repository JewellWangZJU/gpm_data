#!/bin/bash

# ========================================================
# 核心配置区
# ========================================================
BUCKET_NAME="gpm111223"
START_YEAR=2001
# 结束年份 (自动获取当前年份)
END_YEAR=$(date +%Y)

# NASA 数据地址
URL_FINAL="https://gpm1.gesdisc.eosdis.nasa.gov/data/GPM_L3/GPM_3IMERGHH.07"
URL_EARLY="https://gpm1.gesdisc.eosdis.nasa.gov/data/GPM_L3/GPM_3IMERGHHE.07"

COOKIE_FILE="$HOME/.urs_cookies"
CHECKPOINT_FILE="task.progress"  # 用于记录进度的文件
MAX_RETRIES=5                    # 单个任务最大重试次数
# ========================================================

# 检查凭证
if [ ! -s "$HOME/.netrc" ]; then
    echo "❌ 致命错误：找不到 .netrc 文件！请先配置 NASA 登录凭证。"
    exit 1
fi

# --- 功能函数：下载并处理单个任务 ---
process_dataset() {
    local TYPE=$1      # 例如: Final_Run
    local BASE_URL=$2  # URL
    local YEAR=$3      # 年份

    local attempt=1
    local success=0

    echo "   -> 正在处理: [$TYPE] - $YEAR"

    # 重试循环
    while [ $attempt -le $MAX_RETRIES ]; do
        
        # wget 参数解释：
        # --wait=1 --random-wait: 重要！每次请求随机等待 0.5~1.5秒，防止被封 IP
        # --timeout=15: 15秒连不上就超时
        # --tries=3: wget 内部的重试次数
        wget --load-cookies "$COOKIE_FILE" \
             --save-cookies "$COOKIE_FILE" \
             --keep-session-cookies \
             --auth-no-challenge=on \
             -r -np -nH --cut-dirs=3 \
             -e robots=off \
             --wait=1 --random-wait \
             --timeout=15 \
             -A "*.HDF5,*.nc4" \
             -R "*.xml,*.html,*.tmp" \
             "$BASE_URL/$YEAR/"

        # 检查下载结果
        # 如果目录存在且不为空，视为成功
        if [ -d "$YEAR" ] && [ "$(ls -A $YEAR)" ]; then
            echo "   >>> 下载成功！正在上传到 GCS..."
            
            # 上传到 Google Cloud
            gcloud storage cp -r "$YEAR" "gs://$BUCKET_NAME/$TYPE/"
            
            if [ $? -eq 0 ]; then
                echo "   >>> 上传成功。清理本地缓存..."
                rm -rf "$YEAR"
                success=1
                break # 跳出重试循环
            else
                echo "   !!! GCS 上传失败，请检查 GCP 权限。"
                return 1 # 退出函数，报错
            fi
        else
            # 如果是第一次尝试失败，且文件夹不存在，可能是网络被墙
            echo "   !!! 警告：第 $attempt 次尝试下载 $YEAR 失败 (Connection Refused 或 无数据)。"
            echo "   !!! 等待 60 秒后重试..."
            
            # 删除可能残留的空文件夹
            if [ -d "$YEAR" ]; then rm -rf "$YEAR"; fi
            
            sleep 60 # 冷却时间，非常重要
            ((attempt++))
        fi
    done

    if [ $success -eq 0 ]; then
        echo "❌ 错误：$YEAR 年数据在 $MAX_RETRIES 次尝试后依然失败。跳过此年份。"
        return 1
    fi
}

# ========================================================
# 主程序逻辑
# ========================================================

# 1. 读取断点
CURRENT_YEAR=$START_YEAR
if [ -f "$CHECKPOINT_FILE" ]; then
    LAST_FINISHED=$(cat "$CHECKPOINT_FILE")
    # 简单的校验，确保里面是数字
    if [[ "$LAST_FINISHED" =~ ^[0-9]+$ ]]; then
        echo "🔄 检测到进度文件，上次完成到: $LAST_FINISHED 年"
        CURRENT_YEAR=$((LAST_FINISHED + 1))
    fi
fi

echo "🚀 任务开始！将从 $CURRENT_YEAR 年 处理到 $END_YEAR 年"
echo "------------------------------------------------------"

# 2. 年份循环
for (( year=$CURRENT_YEAR; year<=$END_YEAR; year++ ))
do
    echo "======================================="
    echo "📅 正在处理年份: $year"
    echo "======================================="

    # 处理 Final Run
    process_dataset "Final_Run" "$URL_FINAL" "$year"
    
    # 处理 Early Run
    process_dataset "Early_Run" "$URL_EARLY" "$year"

    # 3. 该年份全部成功后，更新断点文件
    echo "$year" > "$CHECKPOINT_FILE"
    echo "✅ 年份 $year 已完成并记录 checkpoint。"
    
    echo "☕ 休息 5 秒防止过热..."
    sleep 5
done

echo "🎉 所有任务全部完成！"
# 任务完成后删除断点文件（可选）
rm -f "$CHECKPOINT_FILE"
