#!/bin/bash

function usage_exit {
    cat <<EOF

$(basename ${0}) is a tool for ...

Usage: ./$(basename ${0}) [監視対象のディレクトリへのパス]

EOF

  exit 1
}

function version {
  echo "$(basename ${0}) version 0.0.1 "
}

# ==========================================
# Generic Methods
# ==========================================
function successLog() {
  echo '['`date '+%H:%M:%S'`']' "$1"
  return 0
}
function getHash() {
  echo `openssl sha1 $1 | awk '{print $2}'`
  return 0
}
function getFileSize() {
  echo `ls -lh $1 | awk '{print $5}'`
  return 0
}
function writeHashLog() {
  echo $1 >>"$HASH_LOG_FILE"
  return 0
}
function writeWatchFileLog() {
  echo $1 >>"$WATCH_LOG_FILE"
  return 0
}
function existsCommand() {
  type $1 2>/dev/null 1>/dev/null
  return 0
}
function errorHandling() {
  echo "$1"
  exit 1
}

# ==========================================
# pngquantを使用したpng画像の最適化
# ==========================================
function optimizeByPngquant() {
  `/usr/local/bin/pngquant --ext .png --speed 1 "$1" --force`
  return 0
}

# ==========================================
# jpegtranを使用したjpeg画像の最適化
# ==========================================
function optimizeByJpegtran() {
  `/usr/local/bin/jpegtran -copy none -optimize -outfile "$1" "$1"`
  return 0
}


# ==========================================
# 画像の圧縮を実行する
#
# $1 - ImageFile
# ==========================================
function optimizeImage() {
  local file=$1
  local fileName=${file##*/}
  local beforeSize=`getFileSize "$file"`
  local fileType=`file $file | awk '{print $2}'`

  if [ "$fileType" = "JPEG" -o "$fileType" = "JPG" ]; then

    optimizeByJpegtran "$file"
  elif [ "$fileType" = "PNG" ]; then

    optimizeByPngquant "$file"
  fi

  local afterSize=`getFileSize "$file"`
  echo `successLog` "optimized $fileName ( $beforeSize => $afterSize )"

  return 0
}

# ==========================================
# 画像が更新されていないかチェック
#
# $1 - ImageFile
# ==========================================
function judgeUpdatedImage() {
  local file=$1
  local hash=`getHash "$file"`

  if [ `grep -c "$hash" "$HASH_LOG_FILE"` -eq 0 ]; then
    # ハッシュ値が変更されていたらファイルが変更されているため新たなハッシュ値を保存する
    optimizeImage "$file"
    writeHashLog `getHash "$file"`
  fi

  return 0
}

# ==========================================
# 定期実行するターゲットディレクトリ内の画像検索
# ==========================================
function watchImages() {
  for file in `\find "$TARGET_DIR" -type f | grep -E ".+.(png|jpg|jpeg)$"`; do
    if [ `grep -c "$file" "$WATCH_LOG_FILE"` -eq 0 ]; then
      # 画像の情報がログファイルに存在しない場合圧縮を実行し、
      # パスとハッシュ値をログファイルに保存する
      optimizeImage "$file"

      writeHashLog `getHash "$file"`
      writeWatchFileLog "$file"
    else
      # 画像の情報がログファイルに存在する場合は更新されていないかを確認
      judgeUpdatedImage "$file"
    fi &
  done
  wait

  return 0
}

# ==========================================
# ログファイルの作成
# ==========================================
function createLogFiles() {
  if [ ! -d "$LOGS_DIR" ]; then
    mkdir "$LOGS_DIR"
    chmod u+x "$LOGS_DIR"
  fi
  if [ ! -f "$WATCH_LOG_FILE" ]; then
    touch "$WATCH_LOG_FILE"
  fi
  if [ ! -f "$HASH_LOG_FILE" ]; then
    touch "$HASH_LOG_FILE"
  fi

  return 0
}

# ==========================================
# 入力コマンド、使用ツールのバリデーション
# ==========================================
function validation() {
  if [ $# -gt 1 -o $# -eq 0 ]; then
    usage_exit
  fi

  if [ ! -e $1 ]; then
    errorHandling "$1: no such directory"
  fi

  if [ ! -d $1 ]; then
    errorHandling "$1 is not directory"
  fi

  if ! existsCommand brew; then
    errorHandling "Please install 'brew'"
  fi

  if ! existsCommand pngquant; then
    echo -e "\n Installing pngquant..."
    brew install pngquant || errorHandling ""
    echo -e "\n Successfully installed pngquant"
  fi &

  if ! existsCommand jpegtran; then
    echo -e "\n Installing jpegtran..."
    brew install jpeg || errorHandling ""
    echo -e "\n Successfully installed jpegtran"
  fi &

  wait

  return 0
}

# ==========================================
# Variables
# ==========================================
readonly WATCH_INTERVAL=1; #秒
readonly TARGET_DIR=$1
readonly LOGS_DIR="$TARGET_DIR/logs"
readonly WATCH_LOG_FILE="$LOGS_DIR/watch.log"
readonly HASH_LOG_FILE="$LOGS_DIR/hash.log"

# ==========================================
# Main
# ==========================================
validation $@
createLogFiles
watchImages

echo -e "\n Watching start... \n"
while true; do
  sleep "$WATCH_INTERVAL"
  watchImages
done
