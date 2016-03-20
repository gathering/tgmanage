NAME='NMS Docker'


ln -s /srv/tgmanage/web/etc/apache2/nms.tg16.gathering.org.conf /etc/apache2/sites-enabled/
ln -s /srv/tgmanage/nms/config.pm /srv/tgmanage/include/
echo 'demo:$apr1$IKrQYF6x$0zmRciLR7Clc2tEEosyHV.' > /srv/tgmanage/web/.htpasswd

/etc/init.d/apache2 restart
echo "go here to look at nms: http://172.17.0.2:8080/"

# Aliases
alias h="history"
alias l="ls -lAhoF --color --show-control-chars"
alias ll="ls -lash --color --show-control-chars"
alias cd..="cd .."

