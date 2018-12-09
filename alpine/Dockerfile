FROM redis:alpine

MAINTAINER Kobozo <yannick@kobozo.be>

LABEL io.trustbuilder.name="tb-redis"

ENV REDIS_CLUSTER_PASS='YmM1MzQ4ZTdmYjIyNTlkZDFlN2MzNzVj'
ENV REDIS_CLUSTER_MASTER_PASS='YmM1MzQ4ZTdmYjIyNTlkZDFlN2MzNzVj'

ENV REDIS_MASTER_HOST=127.0.0.1
ENV REDIS_MASTER_PORT=6379
ENV REDIS_MASTER_NAME=mymaster

ENV DISCOVERY_SERVICE=""

EXPOSE 6379
EXPOSE 26379

COPY files /

RUN apk --no-cache add curl && \
    apk --no-cache add jq

RUN chmod +x /usr/local/*.sh

CMD /usr/local/startup.sh

