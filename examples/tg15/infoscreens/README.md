You need some packages for all this crap, install them:
apt-get install agetty chromium mpv i3 unclutter xdotool

To autologin as your user:
getty@tty6.service belongs in /etc/systemd/system/getty.target.wants/getty@tty6.service

To actually make that user start stuff:
xinitrc belongs in ~/.xinitrc
bash_profile belongs in ~/.bash_profile
start-grid.sh belongs somewhere where you run it after i3 is started
