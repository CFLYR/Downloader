#!/bin/bash

# ================== 配置区 ==================
TOKEN=""          # ← 必须替换
FOLDER_ID="1BBadVSptOe4h8TWchkhWZRLJw8YG_aEi"           # ← 必须替换（最外层文件夹ID）
OUTPUT_DIR="./downloaded_folder"
MAX_DEPTH=10
# ===========================================
mkdir -p "$OUTPUT_DIR"

clean_name() {
    echo "$1" | sed 's/[^[:alnum:]._-]/_/g' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

# 强制从终端读取输入（解决 stdin 被重定向的问题）
confirm_download() {
    local filename="$1"
    local mime="$2"
    echo ""
    echo "  📥 准备下载: $filename"
    echo "  MIME 类型: $mime"
    echo -n "  是否下载？(y/n，回车默认 n): "
    read -r choice < /dev/tty   # ← 关键修复
    case "$choice" in
        [yY]|[yY][eE][sS]) 
            echo "    → 开始下载..."
            return 0 
            ;;
        *) 
            echo "    → 已跳过"
            return 1 
            ;;
    esac
}

download_folder() {
    local current_id="$1"
    local current_path="$2"
    local depth="$3"

    if [[ $depth -gt $MAX_DEPTH ]]; then
        echo "达到最大深度，跳过: $current_path"
        return
    fi

    echo "🔍 正在扫描: $current_path (ID: $current_id)"

    local response
    response=$(curl -s -H "Authorization: Bearer $TOKEN" \
        "https://www.googleapis.com/drive/v3/files?q=%27$current_id%27+in+parents+and+trashed=false&fields=files(id,name,mimeType,shortcutDetails)&pageSize=1000")

    while IFS='|' read -r id name mime target_id target_mime; do
        if [[ -z "$id" || -z "$name" ]]; then continue; fi

        local safe_name=$(clean_name "$name")
        echo "  处理: $safe_name  (MIME: $mime)"

        if [[ "$mime" == "application/vnd.google-apps.shortcut" ]]; then
            if [[ "$target_mime" == "application/vnd.google-apps.folder" && -n "$target_id" ]]; then
                echo "    → 快捷方式指向文件夹，进入..."
                local new_path="$current_path/$safe_name"
                mkdir -p "$OUTPUT_DIR/$new_path"
                download_folder "$target_id" "$new_path" $((depth + 1))
            else
                if confirm_download "$safe_name" "$target_mime"; then
                    curl -H "Authorization: Bearer $TOKEN" \
                        "https://www.googleapis.com/drive/v3/files/$target_id?alt=media" \
                        -o "$OUTPUT_DIR/$current_path/$safe_name"
                fi
            fi

        elif [[ "$mime" == "application/vnd.google-apps.folder" ]]; then
            local new_path="$current_path/$safe_name"
            mkdir -p "$OUTPUT_DIR/$new_path"
            download_folder "$id" "$new_path" $((depth + 1))

        else
            # 所有文件（.pkl、文档等）都走交互
            if confirm_download "$safe_name" "$mime"; then
                if [[ "$mime" == "application/vnd.google-apps.document" ]]; then
                    curl -H "Authorization: Bearer $TOKEN" \
                        "https://www.googleapis.com/drive/v3/files/$id/export?mimeType=application/pdf" \
                        -o "$OUTPUT_DIR/$current_path/${safe_name}.pdf"
                elif [[ "$mime" == "application/vnd.google-apps.spreadsheet" ]]; then
                    curl -H "Authorization: Bearer $TOKEN" \
                        "https://www.googleapis.com/drive/v3/files/$id/export?mimeType=application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" \
                        -o "$OUTPUT_DIR/$current_path/${safe_name}.xlsx"
                else
                    # 普通文件（.pkl）
                    curl -H "Authorization: Bearer $TOKEN" \
                        "https://www.googleapis.com/drive/v3/files/$id?alt=media" \
                        -o "$OUTPUT_DIR/$current_path/$safe_name"
                fi
            fi
        fi
    done < <(echo "$response" | jq -r '.files[]? | "\(.id)|\(.name)|\(.mimeType)|\(.shortcutDetails.targetId // "")|\(.shortcutDetails.targetMimeType // "")"')
}

echo "🚀 开始递归下载（已强制交互提示）..."
download_folder "$FOLDER_ID" "" 0
echo "全部处理完成！文件保存在：$OUTPUT_DIR"
ls -R "$OUTPUT_DIR" 2>/dev/null || echo "目录为空"