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
