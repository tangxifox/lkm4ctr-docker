#!/system/bin/sh
MODDIR=${0%/*}

CONF=/data/adb/lkm4ctr-docker/docker.conf
[ -f "$CONF" ] && . "$CONF"

if [ "${LOAD_KO:-1}" = "1" ] && [ "$(grep -c '^lkm4ctr ' /proc/modules)" = "0" ]; then
  KMITAG=$(uname -r | grep -oE 'android[0-9]+')
  KMAJ=$(uname -r | sed -nE 's/^([0-9]+\.[0-9]+)\..*/\1/p')
  KO=/data/adb/lkm4ctr-docker/ko/lkm4ctr-${KMITAG}-${KMAJ}-arm64.ko
  [ -f "$KO" ] && insmod "$KO"
fi

[ "${START_DOCKER:-1}" = "1" ] || exit 0
if [ -n "$PROXY" ]; then export HTTP_PROXY="$PROXY"; export HTTPS_PROXY="$PROXY"; fi

(
  until [ "$(/system/bin/getprop sys.boot_completed)" = "1" ]; do sleep 2; done

  mkdir -p /data/docker/data /data/docker/run/docker /data/docker/run/containerd /data/docker/conf/containerd /data/docker/plugin /data/docker/conf/ca
  cat /system/etc/security/cacerts/* /data/misc/user/0/cacerts-added/* 2>/dev/null > /data/docker/conf/ca/ca-certificates.crt
  export SSL_CERT_FILE=/data/docker/conf/ca/ca-certificates.crt

  rm -f /data/docker/run/containerd/containerd.sock /data/docker/run/docker.pid
  containerd --config /data/docker/conf/containerd/config.toml > "$MODDIR/containerd.log" 2>&1 &
  i=0
  while [ "$i" -lt 20 ] && [ ! -S /data/docker/run/containerd/containerd.sock ]; do sleep 1; i=$((i+1)); done
  dockerd --config-file=/data/docker/conf/daemon.json > "$MODDIR/dockerd.log" 2>&1 &
  sleep 5
  chmod 666 /data/docker/run/docker.sock 2>/dev/null
) &

exit 0
