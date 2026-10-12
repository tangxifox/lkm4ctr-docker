SKIPUNZIP=0

ui_print " "
ui_print "Docker in /system (lkm4ctr)"
ui_print " "

ui_print "- 架构: $ARCH"
[ "$ARCH" = "arm64" ] || abort "! 仅支持 arm64，当前为 $ARCH"

KMAJ="$(uname -r | sed -nE 's/^([0-9]+\.[0-9]+)\..*/\1/p')"
KTAG="$(uname -r | grep -oE 'android[0-9]+' | head -1)"
RUN_KMI=""
[ -n "$KMAJ" ] && [ -n "$KTAG" ] && RUN_KMI="${KTAG}-${KMAJ}"
ui_print "- 内核: $(uname -r)"
[ -n "$RUN_KMI" ] && ui_print "- KMI: $RUN_KMI"

set_perm_recursive "$MODPATH/system/bin" 0 0 0755 0755
set_perm_recursive "$MODPATH/conf" 0 0 0755 0644
set_perm_recursive "$MODPATH/lkm4ctr" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh"      0 0 0755
set_perm "$MODPATH/uninstall.sh"    0 0 0755

mkdir -p /data/adb/lkm4ctr-docker/ko /data/docker/containerd/root /data/docker/run/containerd \
         /data/docker/conf/containerd /data/docker/run/docker /data/docker/plugin

if [ ! -f /data/adb/lkm4ctr-docker/docker.conf ]; then
  cp -f "$MODPATH/conf/docker.conf" /data/adb/lkm4ctr-docker/docker.conf
  chmod 0644 /data/adb/lkm4ctr-docker/docker.conf
  ui_print "- 已生成开关配置 docker.conf"
fi
if [ ! -f /data/docker/conf/daemon.json ]; then
  cp -f "$MODPATH/conf/daemon.json" /data/docker/conf/daemon.json
  ui_print "- 已生成 daemon.json"
fi
if [ ! -f /data/docker/conf/containerd/config.toml ]; then
  cp -f "$MODPATH/conf/containerd.toml" /data/docker/conf/containerd/config.toml
  ui_print "- 已生成 containerd 配置"
fi

if [ -n "$RUN_KMI" ]; then
  NAME="lkm4ctr-${RUN_KMI}-arm64.ko"
  if [ -f "/data/adb/lkm4ctr-docker/ko/$NAME" ]; then
    ui_print "- 内核模块: 已包含 $NAME"
  else
    ui_print "- 内核模块: 下载 $NAME"
    KO_REPO=cyanmint/lkm4ctr; KO_TAG=""; KO_PROXY=""; GH_PROXY="https://gh-proxy.com"
    [ -f /data/adb/lkm4ctr-docker/docker.conf ] && . /data/adb/lkm4ctr-docker/docker.conf
    if command -v curl >/dev/null 2>&1; then
      PX=""
      [ -n "$KO_PROXY" ] && PX="-x $KO_PROXY"
      [ -n "$KO_TAG" ] || KO_TAG=$(curl $PX -fsSL --max-time 20 "${GH_PROXY}/https://api.github.com/repos/$KO_REPO/releases/latest" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name" *: *"([^"]+)".*/\1/')
      mkdir -p "$MODPATH/lkm4ctr"
      for u in "${GH_PROXY}/https://github.com/$KO_REPO/releases/download/$KO_TAG/$NAME" "${GH_PROXY}/https://github.com/$KO_REPO/releases/latest/download/$NAME"; do
        curl $PX -fsSL -L --max-time 180 -o "/data/adb/lkm4ctr-docker/ko/$NAME" "$u" 2>/dev/null || continue
        [ "$(stat -c%s "/data/adb/lkm4ctr-docker/ko/$NAME" 2>/dev/null || echo 0)" -gt 100000 ] && break
        rm -f "/data/adb/lkm4ctr-docker/ko/$NAME"
      done
      if [ -f "/data/adb/lkm4ctr-docker/ko/$NAME" ]; then
        ui_print "- 内核模块: 下载完成"
      else
        ui_print "! 内核模块下载失败"
      fi
    else
      ui_print "! 没有 curl，跳过下载"
    fi
  fi
fi

ui_print "- 安装完成，重启生效"
ui_print " "
