ARG BUILDER_IMAGE=elixir
ARG VERSION=1.20.3-otp-29-slim@sha256:e39c27c35aeb07448fc99823bce3648ddba86fb47ac6fb3d432bc95022bfe783

FROM ${BUILDER_IMAGE}:${VERSION} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends git build-essential ca-certificates \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force

COPY mix.exs mix.lock /app/
RUN mix deps.get \
  && mix deps.compile

COPY config /app/config/
COPY lib /app/lib/

ARG GIT_COMMIT_SHA1=no_commit
RUN mix release

FROM ${BUILDER_IMAGE}:${VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends curl dnsutils ca-certificates \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app

COPY start.sh /
COPY --from=builder /app/_build/prod/rel/load_test /app/

ENV RELEASE_TMP=/tmp/
ENV RELEASE_COOKIE=changme

CMD [ "/app/bin/load_test", "start"]
