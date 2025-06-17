sudo apt-get update
sudo apt-get install upx git curl unzip -y
LATEST_VERSION=$(curl -s https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main/pool/main/a/alist/ | grep -oE 'title="([^"]+)"' | grep -oE '".+"$' | tr -d '"' | sed -n '2p' | head -n 1 | cut -d _ -f 2)
echo $LATEST_VERSION
LATEST_DOWNLOAD_URL=https://github.com/AlliotTech/openalist/releases/download/beta/alist-linux-arm64.tar.gz
echo $LATEST_DOWNLOAD_URL
mkdir temp
cd temp
curl -s -k $LATEST_DOWNLOAD_URL -o alist.tar.gz
tar -zx alist.tar.gz alist_extract
alist_bin_path=$(pwd)/alist_extract/alist
upx -9 ${alist_bin_path} -o alist_${LATEST_VERSION}_aarch64_upx
mv alist_${LATEST_VERSION}_aarch64_upx ../bin/alist
cd ..
rm -rf temp
ALIST_VERSION=$(grep -oP '^version=\K\S+' module.prop)
sed -i "s/^version=$ALIST_VERSION$/version=v$LATEST_VERSION/" module.prop
zip -r Alist-Server.zip * -x build.sh update.json .github/* 
