pkg update -y && pkg upgrade -y
pkg install git curl jq -y
chmod +x ~/rish
mv ~/rish $PREFIX/bin/
mv ~/rish_shizuku.dex $PREFIX/bin/
cd ~
git clone https://github.com/geminipropkh-sudo/ghost-mode.git
cd ghost-mode
chmod +x ghost_mode.sh
./ghost_mode.sh
