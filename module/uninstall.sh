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
