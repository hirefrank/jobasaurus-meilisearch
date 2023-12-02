FROM alpine:latest

RUN apk --update --no-cache add supervisor
RUN apk --update --no-cache add postgresql-client
RUN apk --update --no-cache add curl
RUN apk --update --no-cache add libc6-compat
RUN apk --update --no-cache --virtual build-dependencies add apache2-utils

RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisord.conf

WORKDIR /jobasaurus-meilisearch

COPY --from=getmeili/meilisearch:latest /bin/meilisearch ./meilisearch
COPY --from=koyeb/koyeb-cli:latest /koyeb ./koyeb
COPY --from=ncarlier/webhookd /usr/local/bin/webhookd /usr/local/bin/webhookd

COPY entrypoint.sh ./entrypoint.sh
COPY index.sh ./index.sh
RUN touch $HOME/.koyeb.yaml

ENV MEILI_HTTP_ADDR=0.0.0.0:7700
EXPOSE 7700 8080

ENTRYPOINT ["/jobasaurus-meilisearch/entrypoint.sh"]