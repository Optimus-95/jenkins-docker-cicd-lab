FROM nginx:alpine

ARG APP_VERSION=1.0
LABEL org.opencontainers.image.version="${APP_VERSION}"

COPY app/index.html /usr/share/nginx/html/index.html

RUN sed -i "s/__APP_VERSION__/${APP_VERSION}/g" \
    /usr/share/nginx/html/index.html

EXPOSE 80

HEALTHCHECK --interval=10s --timeout=3s \
  --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
