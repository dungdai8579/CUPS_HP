#!/bin/sh

# 打印机的 USB ID（通过 lsusb 查看）
PRINTER_USB_ID="03f0:042a"

# 需要跟随打印机连接状态启停的容器列表
CONTAINERS="cups_hp scanservjs_m1136"

# 检查打印机是否已连接
printer_connected() {
    lsusb | grep -q "$PRINTER_USB_ID"
}

# 主循环
while true; do
    if printer_connected; then
        for c in $CONTAINERS; do
            if ! docker ps --format '{{.Names}}' | grep -qx "$c"; then
                echo "打印机已连接，启动容器 $c ..."
                docker start "$c"
            fi
        done
    else
        for c in $CONTAINERS; do
            if docker ps --format '{{.Names}}' | grep -qx "$c"; then
                echo "打印机已断开，停止容器 $c ..."
                docker stop "$c"
            fi
        done
    fi
    sleep 10
done