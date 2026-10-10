#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# 清理 Termux 侧的 docker 环境
# 前提：Magisk 模块 lkm4ctr-docker 已刷入并重启（/system/bin 里已有全套）
# 用法：bash cleanup-termux-docker.sh
# ============================================================
set -u
BIN=$PREFIX/bin
say() { printf '%s\n' "$*"; }

say "== 1. 停掉 Termux 侧拉起的进程 =="
pkill -f 'dockerd --config-file' 2>/dev/null
pkill -f 'containerd --config' 2>/dev/null
pkill -f containerd-shim-runc-v2 2>/dev/null
sleep 2
if pgrep -af 'dockerd|containerd' >/dev/null 2>&1; then
  say "  仍有残留进程，请手动确认："
  pgrep -af 'dockerd|containerd'
else
  say "  已全部停止"
fi

say "== 2. 删除 Termux 里的 docker 二进制 =="
for b in docker dockerd containerd containerd-shim-runc-v2 ctr runc \
         docker-init docker-proxy fuse-overlayfs; do
  if [ -e "$BIN/$b" ]; then rm -f "$BIN/$b"; say "  - 删除 $BIN/$b"; fi
done

say "== 3. 卸载通过 pkg 安装的相关包 =="
for p in docker-cli docker-compose docker; do
  if dpkg -l 2>/dev/null | grep -q "^ii  $p "; then
    pkg uninstall -y "$p" >/dev/null 2>&1 && say "  - 已卸载 $p" || say "  ! $p 卸载失败"
  fi
done

say "== 4. 清理旧 socket / pid / 临时文件 =="
rm -f /data/docker/exec/docker.sock /data/docker/exec/docker.pid \
      /data/docker/docker.pid /data/docker/containerd.log 2>/dev/null
rm -rf "$HOME/lkm4ctr-docker-build" 2>/dev/null
rm -f  "$HOME"/*.bak "$HOME"/containerd.log "$HOME"/dockerd.log \
       "$HOME"/docker.tgz "$HOME"/lkm4ctr-*.ko "$HOME"/lkm4ctr_checker-arm64 \
       "$HOME"/patch_run_paths.py "$HOME"/patch_dockerd.py 2>/dev/null
rm -rf "$HOME/docker" 2>/dev/null
say "  已清理"

say "== 5. 以下内容保留（未删） =="
say "  /data/docker                      数据根目录（镜像层，删了要重新 pull）"
say "  /data/docker/daemon.json          模块生成的 daemon 配置"
say "  /data/docker/containerd/          外部 containerd 的配置与状态"
say "  /data/docker/ca/                  CA bundle"
say "  /data/adb/lkm4ctr-docker/         模块开关与日志"

say "== 6. 复查 PATH 里的命令来源 =="
for b in docker dockerd containerd containerd-shim-runc-v2 ctr runc fuse-overlayfs; do
  printf '  %-26s %s\n' "$b" "$(command -v "$b" 2>/dev/null || echo '不在 PATH')"
done
say "  期望：全部指向 /system/bin/*（模块提供）"

say ""
say "如果要彻底重置（连镜像一起删）："
say "  sudo rm -rf /data/docker /data/container /data/adb/lkm4ctr-docker"
say "  然后重新刷一次模块（或在 Magisk 里停用再启用）"
