FROM hexpm/elixir:1.20.0-rc.6-erlang-27.3.4.9-debian-bookworm-20260518 AS builder

WORKDIR /app
ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
COPY lib lib
RUN mix compile

RUN mix release

FROM debian:bookworm-slim AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates libstdc++6 openssl curl && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash app

WORKDIR /home/app
COPY --from=builder --chown=app:app /app/_build/prod/rel/ex_logdrain ./
RUN mkdir -p storage && chown app:app storage

USER app
ENV PORT=4000
ENV LANG=C.UTF-8
ENV ELIXIR_ERL_OPTIONS="+fnu"
ENV DUCKDB_HOME=/tmp

EXPOSE 4000
CMD ["bin/ex_logdrain", "start"]
