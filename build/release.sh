#!/data/data/com.termux/files/usr/bin/bash
# 打包发布：生成 zip 并计算校验值
set -eu
cd "$(dirname "$0")/.."

echo "==> 生成模块"
bash build/build_lkm4ctr_docker_module.sh

ZIP="$HOME/lkm4ctr-docker.zip"
[ -f "$ZIP" ] || { echo "没找到 $ZIP"; exit 1; }

mkdir -p dist
cp "$ZIP" dist/
echo "==> 产物"
ls -la dist/lkm4ctr-docker.zip
( cd dist && sha256sum lkm4ctr-docker.zip > lkm4ctr-docker.zip.sha256 && cat lkm4ctr-docker.zip.sha256 )
