# 安装与验证

## 前置

- Android 设备，已 root，已装 Magisk
- Termux（用于生成模块）

## 一、生成模块

```sh
pkg install python zip curl -y
bash build/build_lkm4ctr_docker_module.sh
```

生成器依次做：

1. 检查 9 个二进制是否齐全（缺任一即中止）
2. 从 uname -r 识别 KMI：6.1.75-android14-11-g... -> android14-6.1
3. 下载 lkm4ctr-<KMI>-arm64.ko（优先本地文件，其次 Release，可走加速前缀）
4. 复制二进制进模块 system/bin，并在副本上打两个 /run 补丁
5. 写入 module.prop / 四个脚本 / 三个配置 / system/etc/resolv.conf
6. 打包为 ~/lkm4ctr-docker.zip

可用环境变量：

```sh
PROXY=http://172.16.0.254:8000      # HTTP 代理（下载用）
GH_PROXY=https://gh-proxy.com       # GitHub 加速前缀，留空直连
BIN_DIR=$PREFIX/bin                 # 二进制来源目录
```

## 二、刷入

Magisk App -> 模块 -> 从本地安装 -> 选 lkm4ctr-docker.zip -> 重启

若已存在 /data/docker/daemon.json 或 containerd/config.toml，安装脚本不会覆盖，
需要先删除旧文件（或用编辑方式合并新键）。

## 三、开机流程（module/service.sh）

```sh
# 最前面：内核模块（绝对路径，已加载则跳过）
[ "$(grep -c '^lkm4ctr ' /proc/modules)" = "0" ] && insmod /data/adb/modules/lkm4ctr-docker/lkm4ctr/lkm4ctr-<KMI>-arm64.ko

# 其余丢后台：等 sys.boot_completed -> 建目录 -> 合并 CA -> 清残留 socket/pid
#              -> containerd（等 socket 就绪）-> dockerd -> chmod 666 socket
( ... ) &
exit 0
```

两个设计要点：

- 整个流程丢后台：service.sh 立即返回，避免与 sys.boot_completed 互相等待导致卡开机
- insmod 放在最前面：内核模块与开机状态无关

## 四、验证

```sh
su
grep -c '^lkm4ctr ' /proc/modules                 # 1
ls -l /data/docker/run/docker.sock /data/docker/containerd/containerd.sock
docker info | grep -i "storage driver"            # fuse-overlayfs
docker run --rm --network=host alpine sh -c 'echo pid1=$(cat /proc/1/comm); uname -m'
```

## 五、手动控制

```sh
# 启动（开机已自动执行；手动等价命令）
su
export SSL_CERT_FILE=/data/docker/ca/ca-certificates.crt
containerd --config /data/docker/containerd/config.toml >>/data/adb/lkm4ctr-docker/containerd.log 2>&1 &
sleep 3
dockerd --config-file=/data/docker/daemon.json >>/data/adb/lkm4ctr-docker/dockerd.log 2>&1 &

# 停止
pkill dockerd; pkill containerd-shim-runc-v2; pkill 'containerd --config'

# 整段重来
sh /data/adb/modules/lkm4ctr-docker/service.sh
```

## 六、配置项

`/data/adb/lkm4ctr-docker/docker.conf`：

```sh
LOAD_KO=1                 # 是否开机 insmod
START_DOCKER=1
PROXY=                    # dockerd 出网代理，例 http://172.16.0.254:8000
AUTO_DOWNLOAD_KO=1        # 安装时缺 ko 是否自动下载
KO_REPO=cyanmint/lkm4ctr
KO_TAG=                   # 锁定 Release 版本，留空跟随最新
KO_PROXY=                 # 下载走 HTTP 代理
GH_PROXY=https://gh-proxy.com
REMOVE_DATA_ON_UNINSTALL=0
```

`/data/docker/daemon.json` 关键键：

```json
{
  "storage-driver": "fuse-overlayfs",
  "data-root": "/data/docker/data",
  "exec-root": "/data/docker/run/docker",
  "hosts": ["unix:///data/docker/run/docker.sock"],
  "containerd": "/data/docker/containerd/containerd.sock",
  "registry-mirrors": ["https://gh-proxy.org/docker"],
  "bridge": "none", "iptables": false, "userland-proxy": false
}
```
