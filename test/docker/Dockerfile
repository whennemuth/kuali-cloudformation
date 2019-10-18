ARG SERVICE=KC

FROM node:8 AS BASELINE

RUN \
  apt-get update -y && \
  apt-get install -y apt-file && \
  apt-file update -y && \
  apt-get install -y vim

FROM BASELINE AS KC_PACKED
WORKDIR /app
COPY content.kc.tar.gz /tmp/content.tar.gz
RUN tar -xzvf /tmp/content.tar.gz

FROM BASELINE AS COI_PACKED
WORKDIR /app
COPY content.coi.tar.gz /tmp/content.tar.gz
RUN tar -xzvf /tmp/content.tar.gz

FROM ${SERVICE}_PACKED AS PACKED

FROM BASELINE AS INSTALLED
WORKDIR /app
COPY --from=PACKED /app /app
COPY package*.json ./
RUN npm install

FROM INSTALLED AS HTTP
COPY index.js ./index.js
EXPOSE 8080
CMD [ "node", "index.js" ]

FROM INSTALLED AS HTTPS
COPY index.ssl.js ./index.js
RUN \
  mkdir ssl && \
  openssl req \
    -x509 \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -out ssl/localhost.crt \
    -keyout ssl/private.key \
    -subj "/C=US/ST=MA/L=Boston/O=BU/OU=IST/CN=localhost" \
    -days 3650
EXPOSE 8080
EXPOSE 443
CMD [ "node", "index.js" ]