# CUPS HP 打印服务 Docker 镜像

基于 Debian 12 (Bookworm) 的 CUPS 打印服务 Docker 镜像，内置 HPLIP 驱动及 HP 专有插件，适用于需要专有插件的惠普打印机（如 HP LaserJet Professional M1136 MFP）。

部署在局域网中作为共享打印中枢，支持 Windows、macOS、Linux 及 iOS（AirPrint）设备发现和打印。

## 快速开始

### 构建镜像

```bash
docker build -t cups_hp:v2 .
```

### 启动容器

```bash
docker run -d --name cups_hp --privileged --device /dev/bus/usb -p 631:631 cups_hp:v2 /usr/sbin/cupsd -f
```

### 配置打印机

访问 CUPS 管理页面添加打印机：

```
http://<宿主机IP>:631
```

> 用户名和密码均为 `root`

## OpenWrt/iStoreOS 配置 Avahi 广播（AirPrint）

安装 Avahi：

```bash
opkg update
opkg install avahi-daemon avahi-utils
```

创建 Avahi 服务文件 `/etc/avahi/services/airprint.service`：

> 请根据实际情况替换 `rp`、`ty`、`adminurl` 字段值。

```xml
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>Printer</name>
  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtver=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>rp=printers/HP_LaserJet_Professional_M1136_MFP</txt-record>
    <txt-record>ty=HP_LaserJet_Professional_M1136_MFP</txt-record>
    <txt-record>adminurl=http://192.168.100.1:631/printers/HP_LaserJet_Professional_M1136_MFP</txt-record>
    <txt-record>note=HP_LaserJet_Professional_M1136_MFP</txt-record>
    <txt-record>priority=0</txt-record>
    <txt-record>product=(GPL Ghostscript)</txt-record>
    <txt-record>printer-state=3</txt-record>
    <txt-record>printer-type=0x801046</txt-record>
    <txt-record>Transparent=T</txt-record>
    <txt-record>Binary=T</txt-record>
    <txt-record>Fax=F</txt-record>
    <txt-record>Color=T</txt-record>
    <txt-record>Duplex=T</txt-record>
    <txt-record>Staple=F</txt-record>
    <txt-record>Copies=T</txt-record>
    <txt-record>Collate=F</txt-record>
    <txt-record>Punch=F</txt-record>
    <txt-record>Bind=F</txt-record>
    <txt-record>Sort=F</txt-record>
    <txt-record>Scan=F</txt-record>
    <txt-record>pdl=application/octet-stream,application/pdf,application/postscript,image/jpeg,image/png,image/urf</txt-record>
    <txt-record>URF=W8,SRGB24,CP1,RS600</txt-record>
  </service>
</service-group>
```

重启 Avahi 服务：

```bash
/etc/init.d/avahi-daemon restart
```

## 容器启停跟随打印机连接状态

打印机长时间无任务会自动关机，重新开机后容器内的 CUPS 可能无法识别。通过监控脚本让容器启停自动跟随打印机的 USB 连接状态。

创建 `/usr/local/monitor_hp_printer.sh`：

> 请将 `PRINTER_USB_ID` 替换为你的打印机 USB ID，可通过 `lsusb` 命令查看。

```bash
#!/bin/sh

# 打印机的 USB ID（通过 lsusb 查看）
PRINTER_USB_ID="03f0:042a"

# Docker 容器名称
DOCKER_CONTAINER_NAME="cups_hp"

# 检查打印机是否已连接
printer_connected() {
    lsusb | grep -q "$PRINTER_USB_ID"
}

# 主循环
while true; do
    if printer_connected; then
        if ! docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
            echo "打印机已连接，启动 Docker 容器..."
            docker start "$DOCKER_CONTAINER_NAME"
        fi
    else
        if docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
            echo "打印机已断开，停止 Docker 容器..."
            docker stop "$DOCKER_CONTAINER_NAME"
        fi
    fi
    sleep 10
done
```

设置权限并运行：

```bash
chmod +x /usr/local/monitor_hp_printer.sh
/usr/local/monitor_hp_printer.sh &
```

开机自启动：编辑 `/etc/rc.local`，添加：

```bash
/usr/local/monitor_hp_printer.sh &
```

## scanservjs 网页扫描服务

基于 [scanservjs](https://github.com/sbs20/scanservjs) 官方镜像，补齐 HPLIP / hpaio / HP plugin，适配 HP M1136 等需要专有插件的 HP USB 一体机，通过浏览器即可发起扫描。

与 CUPS 打印容器独立部署，互不干扰：

| 容器 | 用途 | 端口 | Dockerfile |
|------|------|------|------------|
| `cups_hp` | 打印 | `631` | `Dockerfile` |
| `scanservjs_m1136` | 扫描 | `8080` | `Dockerfile.scanservjs` |

### 构建镜像

```bash
docker build -f Dockerfile.scanservjs -t scanservjs_m1136:latest .
```

### 启动容器

```bash
mkdir -p /mnt/mmc0-4/scans
docker rm -f scanservjs_m1136 2>/dev/null || true

docker run -d \
  --name scanservjs_m1136 \
  --privileged \
  --device /dev/bus/usb \
  -p 8080:8080 \
  -v /var/run/dbus:/var/run/dbus \
  -v /mnt/mmc0-4/scans:/var/lib/scanservjs/output \
  --restart unless-stopped \
  scanservjs_m1136:latest
```

> `/mnt/mmc0-4/scans` 为扫描文件在宿主机上的保存目录，可按需修改。

### 验证扫描头

```bash
docker exec -it scanservjs_m1136 scanimage -L
```

正常输出：

```text
device `hpaio:/usb/HP_LaserJet_Professional_M1136_MFP?...` is a Hewlett-Packard HP_LaserJet_Professional_M1136_MFP all-in-one
```

### 网页使用

浏览器访问：

```
http://<宿主机IP>:8080
```

同一局域网内的 macOS、Windows、iPhone/iPad 等设备均可访问。

- 点击 **扫描** 按钮发起扫描（"预览"仅更新预览图，不会保存文件）
- 扫描完成后，点击右上角 **文件** 可下载 PNG/JPG/PDF
- 宿主机上的文件保存在启动时挂载的目录：`/mnt/mmc0-4/scans`

### 扫描常见问题

**scanimage -L 看不到设备：**

- 确认容器启动时带了 `--privileged` 和 `--device /dev/bus/usb`
- 确认打印机已通电并通过 USB 连接到宿主机（`lsusb` 可验证）

**扫描后"文件"里没有文件：**

1. 确认点的是"扫描"而非"预览"
2. 放开输出目录权限后重启容器：

   ```bash
   chmod 777 /mnt/mmc0-4/scans
   docker restart scanservjs_m1136
   ```

3. 查看容器日志定位报错：

   ```bash
   docker logs --tail=200 scanservjs_m1136
   ```
4. 实测 HP M1136 在此系统下扫描的分辨率最大为200

**与 CUPS 打印容器共存：**

两个容器可同时运行，但同一时间避免同时打印和扫描，因为底层共用同一台 USB 设备。

## 常见问题

### PDF/图片打印极慢（Word 正常）

**症状**：打印 PDF 或图片时，CUPS 任务面板显示数据体积远大于原始文件（如 175KB 图片显示 15MB），长时间停留在 "processing - 正在向打印机发送数据"。

**原因**：HP 专有插件版本与 HPLIP 驱动版本不匹配，导致光栅化走低效回退路径。

**排查**：

```bash
docker exec -it cups_hp hp-check -r 2>/dev/null | grep -i plugin
# 如果显示 INCOMPAT 说明插件版本不兼容

docker exec -it cups_hp ls -la /usr/share/hplip/prnt/plugins/
# 确认 lj.so 等插件文件存在
```

**解决**：重新构建镜像（安装脚本会自动匹配 HPLIP 版本下载对应插件）：

```bash
docker stop cups_hp && docker rm cups_hp
docker rmi cups_hp:v2
docker build --no-cache -t cups_hp:v2 .
docker run -d --name cups_hp --privileged --device /dev/bus/usb -p 631:631 cups_hp:v2 /usr/sbin/cupsd -f
```

> 重建后需要在 CUPS 管理页面重新添加打印机。

### hp-check 显示 INCOMPAT 但打印正常

Debian 打包的 HPLIP 版本号带有后缀（如 `3.22.10+dfsg0-2`），而插件注册的版本为 `3.22.10`，`hp-check` 的字符串校验会误报 INCOMPAT。只要 `/usr/share/hplip/prnt/plugins/lj.so` 文件存在且打印功能正常，可以忽略此警告。

### 基础镜像版本说明

Dockerfile 锁定使用 `debian:bookworm-slim`（Debian 12）而非 `debian:stable-slim`，因为当 Debian stable 滚动到新版本（如 Debian 13）时，仓库中的 HPLIP 版本可能在 [openprinting.org](https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/) 上没有对应的插件，导致安装失败。

## 参考资料

- [HPLIP 官方下载](https://developers.hp.com/hp-linux-imaging-and-printing/gethplip)
- [HPLIP 源码](https://sourceforge.net/projects/hplip/files/hplip/)
- [HPLIP Plugin 下载](https://www.openprinting.org/download/printdriver/auxfiles/HP/plugins/)
- [scanservjs GitHub](https://github.com/sbs20/scanservjs)
- [原理参考](https://enita.cn/2022/0622/9bfa6627568d/)
- [虚拟机安装参考 1](https://post.smzdm.com/p/a905p290/)
- [虚拟机安装参考 2](https://www.zhoujie218.top/archives/2537.html)
