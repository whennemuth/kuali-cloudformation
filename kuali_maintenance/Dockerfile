FROM nginx:latest
WORKDIR /
COPY ./index.htm /usr/share/nginx/html/index.html
COPY ./env.js /usr/share/nginx/html/env.js
COPY ./env.sh /env.sh
COPY ./default.conf /etc/nginx/conf.d/default.conf
# The files created by the following command produce are self-signed certificate and key.
# These are typically overridden by files mounted to the container from outside, that are 
# issued from a signing authority and won't produce warnings in the browser.
RUN openssl req -newkey rsa:4096 \
    -x509 \
    -sha256 \
    -days 3650 \
    -nodes \
    -out /etc/nginx/nginx.crt \
    -keyout /etc/nginx/nginx.key \
    -subj "/C=US/ST=MA/L=Boston/O=BU/OU=IST/CN=Ec2Instance"
CMD ["/bin/bash", "/env.sh"]
