# 使用 Debian 12 (Bookworm) 精简版作为基础镜像
# 锁定版本而非使用 stable，确保 hplip 3.22.10 与 openprinting.org 插件版本匹配
FROM debian:bookworm-slim

# 设置维护者信息
LABEL maintainer="ysk666666@126.com"

# 将配置文件复制到镜像中指定路径
COPY cupsd.conf /root/cupsd.conf
COPY install_hp_plugin.sh /root/install_hp_plugin.sh


# 更新包管理器并安装需要的软件
RUN apt update && \
    apt install -y hplip gnupg expect cups wget && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# 给予脚本执行权限
RUN chmod +x /root/install_hp_plugin.sh

# 安装hp-plugin（脚本会自动匹配当前 hplip 版本下载对应插件）
RUN expect /root/install_hp_plugin.sh

# 验证插件安装是否成功（构建时就能发现问题）
RUN hp-plugin --status 2>&1 | tee /tmp/hp-plugin-status.log || true

# 使用拷贝的cups配置文件, 所有权限放开
COPY cupsd.conf /etc/cups/cupsd.conf

# 暴露 CUPS 默认端口
EXPOSE 631

# 设置启动命令
CMD ["/usr/sbin/cupsd", "-f"]