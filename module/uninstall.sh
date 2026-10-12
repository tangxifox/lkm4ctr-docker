CONF=/data/adb/modules/lkm4ctr-docker/conf/docker.conf
REMOVE_DATA_ON_UNINSTALL=0
[ -f "$CONF" ] && . "$CONF"
pkill -f dockerd 2>/dev/null
pkill -f containerd-shim-runc-v2 2>/dev/null
pkill -f 'containerd --config' 2>/dev/null
sleep 1
exit 0
