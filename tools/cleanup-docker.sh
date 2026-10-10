#!/system/bin/sh
# ============================================================
# 清理设备上的 docker 环境（纯 Android，不依赖 Termux）
# 用法:  su -c 'sh /data/local/tmp/cleanup-docker.sh'          # 默认停机
#        su -c 'sh /data/local/tmp/cleanup-docker.sh keep'     # 不停进程，只清文件
# ============================================================
set -u
MODE="${1:-stop}"
TB=/data/data/com.termux/files/usr/bin
say() { echo "$*"; }

if [ "$MODE" = "stop" ]; then
  say "== 1. 停止 docker 相关进程 =="
  pkill -f 'dockerd' 2>/dev/null && say "  - 已停止 dockerd"
  pkill -f 'containerd-shim-runc-v2' 2>/dev/null && say "  - 已停止 shim"
  pkill -f 'containerd --config' 2>/dev/null && say "  - 已停止 containerd"
  sleep 2
  if ps -A 2>/dev/null | grep -E 'dockerd|containerd' | grep -v grep >/dev/null 2>&1; then
    say "  仍有残留:"; ps -A 2>/dev/null | grep -E 'dockerd|containerd' | grep -v grep
  else
    say "  已全部停止"
  fi
else
  say "== 1. keep 模式，跳过停止进程 =="
fi

say "== 2. 删除 Termux 目录下的 docker 二进制（若存在）=="
for b in docker dockerd containerd containerd-shim-runc-v2 ctr runc \
         docker-init docker-proxy fuse-overlayfs; do
  if [ -e "$TB/$b" ]; then rm -f "$TB/$b"; say "  - $TB/$b"; fi
done

say "== 3. 清理旧 socket / pid / 临时文件 =="
rm -f /data/docker/exec/docker.sock /data/docker/exec/docker.pid \
      /data/docker/docker.pid /data/local/tmp/containerd.log \
      /data/local/tmp/dockerd.log 2>/dev/null
say "  完成"

say "== 4. 保留项（未删） =="
say "  /data/docker                     数据根目录（镜像层）"
say "  /data/docker/daemon.json         模块生成的配置"
say "  /data/docker/containerd/         外部 containerd 配置与状态"
say "  /data/docker/ca/                 CA bundle"
say "  /data/adb/lkm4ctr-docker/        模块开关与日志"

say "== 5. 复查命令来源 =="
for b in docker dockerd containerd containerd-shim-runc-v2 ctr runc fuse-overlayfs; do
  printf '  %-26s %s\n' "$b" "$(command -v "$b" 2>/dev/null || echo 未找到)"
done
say "  期望: 全部指向 /system/bin/*（Magisk 模块提供）"

say ""
say "彻底重置（含镜像）: rm -rf /data/docker /data/container /data/adb/lkm4ctr-docker"
say "重新拉起服务:      sh /data/adb/modules/lkm4ctr-docker/service.sh"
