#!/bin/bash
apt-get -y install build-essential git-core pkg-config libfaad-dev libdvbpsi-dev liblivemedia-dev libraw1394-dev libdc1394-22-dev libavc1394-dev libtool libtwolame-dev automake dkms libfontconfig1 libice6 libjpeg62 libmng1 libsm6 libtiff5 libxi6 libxrandr2 libxrender1 fontconfig libgl1-mesa-glx dh-autoreconf linux-headers-amd64 zlib1g-dev unzip libgcrypt-dev libvorbis-dev yasm sudo
dpkg -i desktopvideo_10.6.2a3_amd64.deb

cd libvpx
./configure --enable-shared
make -j20
sudo make install
sudo ldconfig
cd ..

cd x264
./configure --enable-shared
make -j20
sudo make install
sudo ldconfig
cd ..

cd fdk-aac
libtoolize
aclocal
automake --add-missing
autoconf
./configure
make -j20
sudo make install
sudo ldconfig
cd ..

cd ffmpeg
./configure --enable-shared --enable-libx264 --disable-stripping --enable-gpl --enable-nonfree --enable-libvpx --enable-libvorbis --enable-libfdk-aac
make -j20
sudo make install
sudo ldconfig
cd ..

cd vlc
./bootstrap
./configure --disable-dbus --disable-mad --disable-postproc --disable-a52 --disable-glx --disable-fribidi --disable-qt --disable-skins2 --enable-dvbpsi --enable-faad --disable-nls --disable-xcb --disable-sdl --disable-libgcrypt --disable-lua --disable-alsa --disable-v4l2 --enable-libgcrypt --enable-fdkaac --with-decklink-sdk=/root/decklink-sdk/Linux
make -j20
sudo make install
sudo ldconfig
