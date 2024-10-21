# Neurow

Push from backends to frontend at scale


## Repository content
This git repository contains:
- The Neurow server in the `/neurow` directory.
- Load tests in the `/load_test` directory.

Both are independent Elixir mix applications.

## Neurow

All commands provided here must be run in the `/neurow` directory
 
### Setup and start Neurow locally

- Install the latest version of Elixir by following instructions provided [here](https://elixir-lang.org/install.html),
- Run `mix deps.get` to download the dependencies required by Neurow,
- Run `mix run --no-halt` to start Neurow locally with the default development configuration. The public API is then available on `http://localhost:4000` and the internal API on `http://localhost:3000`.

It is possible to override the default local configuration with environment variables. For example to run Neurow on custom ports: `PUBLIC_API_PORT=5000 INTERNAL_API_PORT=5000 mix run --no-halt `


Available environment variables are:

| Name | Default value | Role |
| --- | --- | --- | 
| `LOG_LEVEL` | info | Log level |
| `LOG_FORMAT` | TEXT | Log format, possible values: `TEXT` - space separated attributes, `ECS` - JSON format compatible with the [Elastic Common Schema](https://www.elastic.co/guide/en/ecs/current/index.html) | 
| `PUBLIC_API_PORT` | 4000 | TCP port of the public API |
| `PUBLIC_API_JWT_MAX_LIFETIME` | 120 | Max lifetime in seconds allowed for JWT tokens issued on the public API |
| `PUBLIC_API_CONTEXT_PATH` | "" | URL prefix for resources of the public API - Useful to mount Neurow on a existing website|
| `PREFLIGHT_MAX_AGE` | 86400 | Value of the `access-control-max-age` headers on CROS preflight responses on the public API |
| `SSE_TIMEOUT` | 900000 | SSE deconnection delay in ms, after the last received message
| `SSE_KEEPALIVE` | 600000 | Neurow periodically send `ping` events on SSE connections to prevent connections from being closed by network devices. This variable defines the delay between two ping events in milliseconds. |
| `MAX_HEADER_VALUE_LENGTH`| 8192 | Max http request headers size, as expected by the cowboy HTTP server [here](https://ninenines.eu/docs/en/cowboy/2.12/manual/cowboy_http/) |
| `INTERNAL_API_PORT` | 3000 | TCP port fo the internal API |
| `INTERNAL_API_JWT_MAX_LIFETIME` | 1500 | Max lifetime in seconds allowed for JWT tokens issued on the internal API |
| `HISTORY_MIN_DURATION` | 30 | Messages are persisted in the Neurow cluster, so clients can re-fetch recent messages after a short term disconnection by using the `Last-Event-Id` on SSE connections. Messages are only persisted for a limited time. `HISTORY_MIN_DURATION` defines the minimum retention guaranteed by the Neurow server.


### Generate JWT tokens for the local environment
Both the public and internal APIs rely on JWT tokens for authentication. For now JWT tokens are signed tokens with shared secret keys. Assymetric signatures will be supported later.

Developement issuers and their signature keys are hard coded in `config/runtimes.exs:51`. The available issuers are `test_issuer1` and `test_issuer2`. 

To generate a JWT token for the public API, run:
`mix generate_jwt_token --api=public --issuer=<issuer name> --topic=<topic name>`

To generate a JWT token for the internal API, run:
`mix generate_jwt_token --api=internal --issuer=<issuer name>`


### Run tests
- `mix test` runs all tests (both unit and integration tests)
- `mix test.unit` runs unit tests
- `mix test.integration` run integration tests

## Load tests
WIP
