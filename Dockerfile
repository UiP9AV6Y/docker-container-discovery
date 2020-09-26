ARG IMAGE_FLAVOUR=2.7-slim

FROM ruby:2.7 AS builder

WORKDIR /src

COPY . .
RUN set -xe; \
  gem build *.gemspec \
  && gem install \
    --no-document \
    --platform ruby \
    --without development \
    --install-dir /build \
    *.gem

FROM ruby:${IMAGE_FLAVOUR}

COPY --from=builder /build/ $GEM_HOME/
RUN docker-container-discovery --version

EXPOSE 19053 10053 10053/udp
HEALTHCHECK --start-period=5s --timeout=5s \
  CMD docker-container-discovery-healthcheck
CMD ["docker-container-discovery"]

ARG BUILD_DATE="1970-01-01T00:00:00Z"
ARG VERSION="1.0.0"
ARG VCS_URL="http://localhost/"
ARG VCS_REF="master"
LABEL org.opencontainers.image.created=$BUILD_DATE \
      org.opencontainers.image.title="Docker Container Discovery" \
      org.opencontainers.image.description="Service discovery for Docker containers" \
      org.opencontainers.image.url="https://github.com/UiP9AV6Y/docker-container-discovery" \
      org.opencontainers.image.source=$VCS_URL \
      org.opencontainers.image.revision=$VCS_REF \
      org.opencontainers.image.vendor="Gordon Bleux" \
      org.opencontainers.image.version=$VERSION \
      com.microscaling.docker.dockerfile="/Dockerfile" \
      org.opencontainers.image.licenses="MIT"
