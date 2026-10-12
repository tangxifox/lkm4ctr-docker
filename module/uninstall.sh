CONF=/data/adb/modules/lkm4ctr-docker/conf/docker.conf
REMOVE_DATA_ON_UNINSTALL=0
[ -f "$CONF" ] && . "$CONF"
pkill -f dockerd 2>/dev/null
pkill -f containerd-shim-runc-v2 2>/dev/null
pkill -x containerd 2>/dev/null
sleep 1
[ "$REMOVE_DATA_ON_UNINSTALL" = "1" ] && rm -rf /data/docker
exit 0
