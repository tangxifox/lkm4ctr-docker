#!/system/bin/sh
export PATH=/system/bin:/system/xbin:/data/adb/magisk:$PATH

[ -f /data/adb/modules/lkm4ctr-docker/conf/docker.conf ] && . /data/adb/modules/lkm4ctr-docker/conf/docker.conf

if [ "${LOAD_KO:-1}" = "1" ] && [ "$(grep -c '^lkm4ctr ' /proc/modules)" = "0" ]; then
  KMITAG=$(uname -r | grep -oE 'android[0-9]+')
  KMAJ=$(uname -r | sed -nE 's/^([0-9]+\.[0-9]+)\..*/\1/p')
  if [ -f /data/adb/modules/lkm4ctr-docker/lkm4ctr/lkm4ctr-${KMITAG}-${KMAJ}-arm64.ko ]; then
    insmod /data/adb/modules/lkm4ctr-docker/lkm4ctr/lkm4ctr-${KMITAG}-${KMAJ}-arm64.ko
  fi
fi

[ "${START_DOCKER:-1}" = "1" ] || exit 0
if [ -n "$PROXY" ]; then export HTTP_PROXY="$PROXY"; export HTTPS_PROXY="$PROXY"; fi

(
  until [ "$(/system/bin/getprop sys.boot_completed)" = "1" ]; do sleep 2; done

  mkdir -p /data/docker/data /data/docker/run/docker /data/docker/run/containerd /data/docker/conf/containerd /data/docker/plugin /data/docker/conf/ca
  cat /system/etc/security/cacerts/* /data/misc/user/0/cacerts-added/* 2>/dev/null > /data/docker/conf/ca/ca-certificates.crt
  [ -s /data/docker/conf/ca/ca-certificates.crt ] && export SSL_CERT_FILE=/data/docker/conf/ca/ca-certificates.crt

  rm -f /data/docker/run/containerd/containerd.sock /data/docker/run/docker.pid
  containerd > /data/adb/modules/lkm4ctr-docker/containerd.log 2>&1 &
  i=0
  while [ "$i" -lt 20 ] && [ ! -S /data/docker/run/containerd/containerd.sock ]; do sleep 1; i=$((i+1)); done
  dockerd > /data/adb/modules/lkm4ctr-docker/dockerd.log 2>&1 &
  sleep 5
  chmod 666 /data/docker/run/docker.sock 2>/dev/null
) &

exit 0
