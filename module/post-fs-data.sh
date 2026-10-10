#!/system/bin/sh
# 只建目录，不做任何可能阻塞开机的操作
mkdir -p /data/docker/data /data/docker/run/docker /data/docker/plugin \
         /data/container /data/docker/containerd/root /data/docker/containerd/state
chmod 755 /data/docker /data/docker/run /data/docker/run/docker /data/docker/plugin /data/container 2>/dev/null
