#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Magisk 模块生成器 v2：docker 全家桶挂进 /system/bin
#   - 自动识别 KMI 并下载 lkm4ctr 内核模块
#   - 自动给 containerd / shim / dockerd 打 /run 路径补丁
#   - 开机按 insmod -> containerd -> dockerd 顺序拉起
# 用法：bash build_lkm4ctr_docker_module.sh
# 产物：~/lkm4ctr-docker.zip
# ============================================================
set -eu

MODID=lkm4ctr-docker
KMI=android14-6.1
BIN="${BIN_DIR:-$PREFIX/bin}"
BUILD="$HOME/${MODID}-build"
OUT="$HOME/${MODID}.zip"
PROXY_DEFAULT=""

echo "==> 1. 检查依赖"
BINS="docker dockerd containerd containerd-shim-runc-v2 ctr runc docker-init docker-proxy fuse-overlayfs"
for b in $BINS; do
  [ -x "$BIN/$b" ] || { echo "缺少 $BIN/$b（不设兜底，必须齐）"; exit 1; }
  echo "    ok  $b"
done
command -v zip >/dev/null || { echo "缺少 zip：pkg install zip"; exit 1; }
command -v python >/dev/null || { echo "缺少 python：pkg install python"; exit 1; }

# ---------- KMI 识别 + 自动下载内核模块 ----------
PROXY="${PROXY:-}"
GH_PROXY="${GH_PROXY:-https://gh-proxy.com}"
BUNDLE_KO="${BUNDLE_KO:-1}"   # 0 = 不把 ko 打进包，改由安装时下载
REPO="cyanmint/lkm4ctr"
api() { curl -fsSL ${PROXY:+-x "$PROXY"} --max-time 60 "$@"; }

# KMI = androidNN(来自内核 tag) + major.minor(来自版本前缀)，例：6.1.75-android14-11-gxxx -> android14-6.1
KVER="$(uname -r)"
KMAJ="$(echo "$KVER" | sed -nE 's/^([0-9]+\.[0-9]+)\..*/\1/p')"
KTAG="$(echo "$KVER" | grep -oE 'android[0-9]+' | head -1)"
RUN_KMI=""
[ -n "$KMAJ" ] && [ -n "$KTAG" ] && RUN_KMI="${KTAG}-${KMAJ}"
case "$RUN_KMI" in
  android*) echo "==> 2. 本机 KMI: $RUN_KMI"; KMI="$RUN_KMI";;
  *)        echo "==> 2. 无法识别 KMI，沿用默认: $KMI";;
esac
KO_NAME="lkm4ctr-${KMI}-arm64.ko"

KO_SRC=""
for c in "./${KO_NAME}" "$HOME/${KO_NAME}" "$HOME/downloads/${KO_NAME}" \
         "/sdcard/Download/${KO_NAME}" "$HOME/storage/downloads/${KO_NAME}"; do
  [ -f "$c" ] && { KO_SRC="$c"; echo "    本地已有 $KO_NAME"; break; }
done

TAG=""
if [ -z "$KO_SRC" ] && [ "$BUNDLE_KO" = "1" ]; then
  echo "==> 3. 自动下载 $KO_NAME"
  TAG="$(api "${GH_PROXY}/https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
         | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name" *: *"([^"]+)".*/\1/')"
  [ -n "$TAG" ] && echo "    最新版本: $TAG"
  for url in \
    "${GH_PROXY}/https://github.com/${REPO}/releases/download/${TAG}/${KO_NAME}" \
    "${GH_PROXY}/https://github.com/${REPO}/releases/latest/download/${KO_NAME}" ; do
    [ -n "$TAG" ] || case "$url" in *"/download//"*) continue;; esac
    if api -L -o "$HOME/$KO_NAME" "$url" 2>/dev/null; then
      SZ="$(stat -c%s "$HOME/$KO_NAME" 2>/dev/null || echo 0)"
      if [ "$SZ" -gt 100000 ]; then
        echo "    下载成功 ($SZ 字节)"
        head -c 4 "$HOME/$KO_NAME" | od -An -tx1 | grep -q "7f 45 4c 46" \
          && echo "    ELF 头校验通过" || echo "    !! 不是 ELF"
        KO_SRC="$HOME/$KO_NAME"; break
      fi
    fi
  done
  [ -n "$KO_SRC" ] && echo "    sha256: $(sha256sum "$KO_SRC" | cut -d' ' -f1)"
  [ -n "$KO_SRC" ] || echo "    !! 下载失败，请手动放到 $HOME/$KO_NAME"
fi

CHECKER_SRC=""
for c in "./lkm4ctr_checker-arm64" "$HOME/lkm4ctr_checker-arm64"; do
  [ -f "$c" ] && { CHECKER_SRC="$c"; break; }
done
if [ -z "$CHECKER_SRC" ] && [ -n "$TAG" ]; then
  if api -L -o "$HOME/lkm4ctr_checker-arm64" \
       "${GH_PROXY}/https://github.com/${REPO}/releases/download/${TAG}/lkm4ctr_checker-arm64" 2>/dev/null; then
    [ "$(stat -c%s "$HOME/lkm4ctr_checker-arm64" 2>/dev/null || echo 0)" -gt 10000 ] \
      && { CHECKER_SRC="$HOME/lkm4ctr_checker-arm64"; echo "    checker 已下载"; }
  fi
fi

echo "==> 4. 建目录并复制二进制"
rm -rf "$BUILD"; mkdir -p "$BUILD/$MODID"/{system/bin,conf,lkm4ctr}

cp "$BIN/docker"                     "$BUILD/$MODID/system/bin/docker-real"
cp "$BIN/dockerd"                    "$BUILD/$MODID/system/bin/dockerd"
cp "$BIN/containerd"                 "$BUILD/$MODID/system/bin/containerd"
cp "$BIN/containerd-shim-runc-v2"    "$BUILD/$MODID/system/bin/containerd-shim-runc-v2"
cp "$BIN/ctr"                        "$BUILD/$MODID/system/bin/ctr"
cp "$BIN/runc"                       "$BUILD/$MODID/system/bin/runc"
cp "$BIN/docker-init"                "$BUILD/$MODID/system/bin/docker-init"
cp "$BIN/docker-proxy"               "$BUILD/$MODID/system/bin/docker-proxy"
cp "$BIN/fuse-overlayfs"        "$BUILD/$MODID/system/bin/fuse-overlayfs"
[ "$BUNDLE_KO" = "1" ] && [ -n "$KO_SRC" ] && cp "$KO_SRC" "$BUILD/$MODID/lkm4ctr/$KO_NAME"
[ "$BUNDLE_KO" = "1" ] && [ -n "$CHECKER_SRC" ] && cp "$CHECKER_SRC" "$BUILD/$MODID/lkm4ctr/lkm4ctr_checker-arm64"
chmod 0755 "$BUILD/$MODID/system/bin/"*
[ "$BUNDLE_KO" = "1" ] && [ -n "$CHECKER_SRC" ] && chmod 0755 "$BUILD/$MODID/lkm4ctr/lkm4ctr_checker-arm64"

echo "==> 5. 给模块内的副本打 /run 路径补丁（不动 Termux 里的原件）"
MODBIN="$BUILD/$MODID/system/bin"
python - "$MODBIN" <<'PYEOF'
import os, sys, hashlib
d = sys.argv[1]
PATCHES = [(b'/run/docker/plugins', b'/data/docker/plugin'),   # 19 = 19
           (b'/run/containerd',    b'/data/container')]         # 15 = 15
targets = ['dockerd', 'containerd', 'containerd-shim-runc-v2', 'docker-real']
for t in targets:
    p = os.path.join(d, t)
    if not os.path.exists(p):
        print(f'    跳过 {t}（不存在）'); continue
    data = open(p, 'rb').read()
    total = 0
    for old, new in PATCHES:
        assert len(old) == len(new), (old, new)
        n = data.count(old)
        if n:
            data = data.replace(old, new); total += n
    if total == 0:
        print(f'    {t}: 已是补丁状态'); continue
    open(p, 'wb').write(data)
    print(f'    {t}: 替换 {total} 处, sha256 {hashlib.sha256(data).hexdigest()[:16]}')
PYEOF

echo "==> 6. 写入模块脚本"

cat > "$BUILD/$MODID/system/bin/docker" <<'EOF'
#!/system/bin/sh
# 官方 docker CLI 入口包装：自动指向本模块的 socket
: "${DOCKER_HOST:=unix:///data/docker/run/docker.sock}"
export DOCKER_HOST
exec /system/bin/docker-real "$@"
EOF

cat > "$BUILD/$MODID/module.prop" <<EOF
id=${MODID}
name=Docker in /system (lkm4ctr)
version=v1.0.0
versionCode=1
author=tangxi
description=docker内核ko加载版
EOF





cat > "$BUILD/$MODID/post-fs-data.sh" <<'EOF'
#!/system/bin/sh
# 只建目录，不做任何可能阻塞开机的操作
mkdir -p /data/docker/data /data/docker/run/docker /data/docker/plugin \
         /data/container /data/docker/containerd/root /data/docker/containerd/state
chmod 755 /data/docker /data/docker/run /data/docker/run/docker /data/docker/plugin /data/container 2>/dev/null
EOF

cat > "$BUILD/$MODID/service.sh" <<'EOF'
#!/system/bin/sh
MODDIR=${0%/*}
LOG="$MODDIR/log"

# 脚本最前面加载内核模块（绝对路径；已加载则跳过）
[ "$(grep -c '^lkm4ctr ' /proc/modules)" = "0" ] && insmod /data/adb/modules/lkm4ctr-docker/lkm4ctr/lkm4ctr-android14-6.1-arm64.ko 2>>"$LOG"

# 其余丢后台：service.sh 立刻返回，避免和 sys.boot_completed 互相等死
(
  until [ "$(/system/bin/getprop sys.boot_completed)" = "1" ]; do sleep 2; done

  # 目录 + CA bundle
  mkdir -p /data/docker/data /data/docker/run/docker /data/container /data/docker/ca
  cat /system/etc/security/cacerts/* /data/misc/user/0/cacerts-added/* 2>/dev/null > /data/docker/ca/ca-certificates.crt
  export SSL_CERT_FILE=/data/docker/ca/ca-certificates.crt

  # 容器运行时：先清残留 socket/pid，再依次拉起
  rm -f /data/docker/containerd/containerd.sock /data/docker/run/docker.pid
  containerd --config /data/docker/containerd/config.toml > "$MODDIR/containerd.log" 2>&1 &
  i=0
  while [ "$i" -lt 20 ] && [ ! -S /data/docker/containerd/containerd.sock ]; do sleep 1; i=$((i+1)); done
  dockerd --config-file=/data/docker/daemon.json > "$MODDIR/dockerd.log" 2>&1 &
  sleep 5
  chmod 666 /data/docker/run/docker.sock 2>/dev/null
  echo "$(date '+%m-%d %H:%M:%S') containerd(${i}s) / dockerd 已拉起" >> "$LOG"
) &

exit 0
EOF

cat > "$BUILD/$MODID/uninstall.sh" <<'EOF'
#!/system/bin/sh
CONF=/data/adb/lkm4ctr-docker/docker.conf
REMOVE_DATA_ON_UNINSTALL=0
[ -f "$CONF" ] && . "$CONF"
pkill -f dockerd 2>/dev/null
pkill -f containerd-shim-runc-v2 2>/dev/null
pkill -f 'containerd --config' 2>/dev/null
sleep 1
[ "$REMOVE_DATA_ON_UNINSTALL" = "1" ] && rm -rf /data/docker /data/container /data/adb/lkm4ctr-docker
exit 0
EOF

cat > "$BUILD/$MODID/conf/docker.conf" <<EOF
# 开机自动加载 lkm4ctr 内核模块：1=开（默认）0=关
# 模块自带与内核匹配的 ko；insmod 失败只记日志，不阻塞开机
LOAD_KO=1
# 找不到对应 KMI 的 ko 时自动去 GitHub 下载（需要 curl）
AUTO_DOWNLOAD_KO=1
KO_REPO=cyanmint/lkm4ctr
# 锁定版本号；留空 = 跟随最新 Release（例：4.0.3）
KO_TAG=
# 下载走代理（例：http://172.16.0.254:8000），留空直连
KO_PROXY=
# GitHub 加速前缀（留空则直连 GitHub）
GH_PROXY=https://gh-proxy.com
# 开机自动启动 containerd + dockerd
START_DOCKER=1
# dockerd 出网代理，留空则直连（例：http://172.16.0.254:8000）
PROXY=${PROXY_DEFAULT}
# 内核模块不写死文件名：运行时用 uname -r 识别 KMI，
# 自动拼出 lkm4ctr-<KMI>-arm64.ko，找不到就去 Release 下载同名文件
# 卸载模块时是否连 /data/docker 与 /data/container 一起删
REMOVE_DATA_ON_UNINSTALL=0
EOF

cat > "$BUILD/$MODID/conf/daemon.json" <<'EOF'
{
  "storage-driver": "fuse-overlayfs",
  "data-root": "/data/docker/data",
  "exec-root": "/data/docker/run/docker",
  "pidfile": "/data/docker/run/docker.pid",
  "hosts": ["unix:///data/docker/run/docker.sock"],
  "containerd": "/data/docker/containerd/containerd.sock",

  "bridge": "none",
  "iptables": false,
  "ip6tables": false,
  "ip-forward": false,
  "ip-masq": false,
  "userland-proxy": false,

  "exec-opts": ["native.cgroupdriver=cgroupfs"],
  "no-new-privileges": false,
  "experimental": true,
  "live-restore": false,
  "features": { "buildkit": false },

  "log-driver": "json-file",
  "log-level": "info",
  "log-opts": { "max-size": "10m", "max-file": "3" },

  "registry-mirrors": ["https://gh-proxy.org/docker"],
  "dns": ["223.5.5.5", "8.8.8.8", "1.1.1.1"],
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Soft": 65536, "Hard": 65536 }
  }
}
EOF

cat > "$BUILD/$MODID/conf/containerd.toml" <<'EOF'
version = 3
root  = "/data/docker/containerd/root"
state = "/data/docker/containerd/state"

[grpc]
  address = "/data/docker/containerd/containerd.sock"
EOF

mkdir -p "$BUILD/$MODID/system/etc"
cat > "$BUILD/$MODID/system/etc/resolv.conf" <<'EOF'
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 8.8.8.8
EOF

cat > "$BUILD/$MODID/customize.sh" <<'EOF'
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
set_perm "$MODPATH/system/etc/resolv.conf" 0 0 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh"      0 0 0755
set_perm "$MODPATH/uninstall.sh"    0 0 0755

mkdir -p /data/adb/lkm4ctr-docker/ko /data/docker/containerd/root /data/docker/containerd/state \
         /data/docker/run/docker /data/docker/plugin /data/container

if [ ! -f /data/adb/lkm4ctr-docker/docker.conf ]; then
  cp -f "$MODPATH/conf/docker.conf" /data/adb/lkm4ctr-docker/docker.conf
  chmod 0644 /data/adb/lkm4ctr-docker/docker.conf
  ui_print "- 已生成开关配置 docker.conf"
fi
if [ ! -f /data/docker/daemon.json ]; then
  cp -f "$MODPATH/conf/daemon.json" /data/docker/daemon.json
  ui_print "- 已生成 daemon.json"
fi
if [ ! -f /data/docker/containerd/config.toml ]; then
  cp -f "$MODPATH/conf/containerd.toml" /data/docker/containerd/config.toml
  ui_print "- 已生成 containerd 配置"
fi

if [ -n "$RUN_KMI" ]; then
  NAME="lkm4ctr-${RUN_KMI}-arm64.ko"
  if [ -f "$MODPATH/lkm4ctr/$NAME" ]; then
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
        curl $PX -fsSL -L --max-time 180 -o "$MODPATH/lkm4ctr/$NAME" "$u" 2>/dev/null || continue
        [ "$(stat -c%s "$MODPATH/lkm4ctr/$NAME" 2>/dev/null || echo 0)" -gt 100000 ] && break
        rm -f "$MODPATH/lkm4ctr/$NAME"
      done
      if [ -f "$MODPATH/lkm4ctr/$NAME" ]; then
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
ui_print "- 开机自动加载内核模块: 把 LOAD_KO 改成 1"
ui_print " "
EOF

chmod 0755 "$BUILD/$MODID/post-fs-data.sh" "$BUILD/$MODID/service.sh" \
           "$BUILD/$MODID/uninstall.sh" "$BUILD/$MODID/customize.sh" \
           "$BUILD/$MODID/system/bin/docker"

echo "==> 7. 打包"
rm -f "$OUT"
( cd "$BUILD/$MODID" && zip -rq "$OUT" . )
echo "==> 完成: $OUT  ($(du -h "$OUT" | cut -f1))"
echo
echo "刷入: Magisk App -> 模块 -> 从本地安装 -> $OUT -> 重启"
echo "验证: docker run --rm --network=host alpine uname -m ; docker info | grep -i 'storage driver'"
