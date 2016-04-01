#!/bin/bash

   openssl req -new -sha256 -key /root/le/keys/domain.key -subj "/" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=DNS:yoda.tg16.gathering.org,DNS:stream.tg16.gathering.org,DNS:streams.tg16.gathering.org,DNS:webcam.tg16.gathering.org,DNS:webcams.tg16.gathering.org,DNS:nms.tg16.gathering.org,DNS:nms-public.tg16.gathering.org,DNS:stats.tg16.gathering.org,DNS:nms-api.tg16.gathering.org")) > /root/le/csrs/yoda.csr
   python /root/le/acme-tiny/acme_tiny.py --account-key /root/le/keys/account.key --csr /root/le/csrs/yoda.csr --acme-dir /var/www/html/.well-known/acme-challenge > /root/le/certs/yoda.crt
   if [ $? -ne 0 ]; then
   echo "Client exited with error, not overwriting cert"
   else
   cp /root/le/certs/yoda.crt /root/le/prodcerts/yoda.prod.crt
   fi

curl https://letsencrypt.org/certs/lets-encrypt-x1-cross-signed.pem > /root/le/letsencrypt.ca-bundle.temp
if [ $? -ne 0 ]; then
echo "Client exited with error, not overwriting cert"
else
mv /root/le/letsencrypt.ca-bundle.temp /root/le/letsencrypt.ca-bundle
fi
