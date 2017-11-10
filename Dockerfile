FROM elixir:1.5.2-alpine as asset-builder-mix-getter

ENV HOME=/opt/app

RUN mix do local.hex --force, local.rebar --force

# Cache elixir deps
COPY config/ $HOME/config/
COPY mix.exs mix.lock $HOME/

WORKDIR $HOME/

RUN mix deps.get

########################################################################

FROM node:6 as asset-builder

ENV HOME=/opt/app
WORKDIR $HOME

COPY --from=asset-builder-mix-getter $HOME/deps $HOME/deps

WORKDIR $HOME/assets
COPY assets/ ./
RUN yarn install
RUN ./node_modules/.bin/brunch build --production

########################################################################
FROM bitwalker/alpine-elixir:1.5.2 as releaser

ENV HOME=/opt/app

# dependencies for comeonin
RUN apk add --no-cache build-base cmake

# Install Hex + Rebar
RUN mix do local.hex --force, local.rebar --force

ARG ERLANG_COOKIE
ENV NODE_COOKIE $ERLANG_COOKIE

RUN echo $ERLANG_COOKIE
RUN printenv

# Cache elixir deps
COPY config/ $HOME/config/
COPY mix.exs mix.lock $HOME/

ENV MIX_ENV=prod
RUN mix do deps.get --only $MIX_ENV, deps.compile

COPY . $HOME/

# Digest precompiled assets
COPY --from=asset-builder $HOME/priv/static/ $HOME/priv/static/

RUN mix phx.digest

# Release
WORKDIR $HOME
RUN mix release --env=$MIX_ENV --verbose
RUN ls -la

########################################################################
FROM alpine:3.6

ENV LANG=en_US.UTF-8 \
    HOME=/opt/app/ \
    TERM=xterm

ARG ERLANG_COOKIE
ENV ERLANG_COOKIE $ERLANG_COOKIE

ENV MYPROJECT_VERSION=0.0.2

RUN apk add --no-cache ncurses-libs openssl bash

EXPOSE 5000
ENV PORT=5000 \
    MIX_ENV=prod \
    REPLACE_OS_VARS=true \
    SHELL=/bin/sh

COPY --from=releaser $HOME/_build/prod/rel/phoenix_test/releases/$MYPROJECT_VERSION/phoenix_test.tar.gz $HOME
WORKDIR $HOME

RUN echo "Checking erlang distribution cookie"
RUN printenv
RUN ls -la

RUN tar -xzf phoenix_test.tar.gz

ENTRYPOINT ["/opt/app/bin/phoenix_test"]
CMD ["foreground"]
