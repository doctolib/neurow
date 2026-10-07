ARG BUILDER_IMAGE=elixir
ARG VERSION=1.20.4-otp-29-slim@sha256:2a26b8aac0cdbd004c646eb51d8791fa4d2f102359b40a9717cd988523532bf6

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
  && apt-get install -y --no-install-recommends curl dnsutils \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir /app
WORKDIR /app

COPY start.sh iex.sh /
COPY --from=builder /app/_build/prod/rel/neurow /app/

ENV RELEASE_TMP=/tmp/
ENV RELEASE_COOKIE=changme

CMD ["/start.sh" ]
