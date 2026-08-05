ARG BUILDER_IMAGE=elixir
ARG VERSION=1.20.2-otp-29-slim@sha256:e500da1777164f9be05f7ffc0fe06cdb692f453bf7d651755e72310ec8a92eed

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
