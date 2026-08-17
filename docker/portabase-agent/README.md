# Portabase Agent
This is intended to be used as a template. At the time of writing, Portabase Agents have a bit of a chicken and egg problem. There is no way to natively pass the agent any secrets in a secure and rotatable way. The only 2 methods of configuration are:
- Configuration by Portabase CLI
  - Interactive only
  - Still stores secrets in plain text on the docker host
- Create the config.json (or config.toml) file manually
  - Stores secrets in plain text on the docker host

Even if there was a programmatic way to load the agent configuration, there is still the issue of docker networks. The agent has to either be attached to the docker network, or a new network has to be created, and the DB container has to be attached to the new network. There are also alternative paths, such as exposing DB ports locally.

There is also no way to configure agents via the Portabase Dashboard or the API. You can create an agent configuration and even get an edge key provisioned, but actual database and docker volume configuration has to be set via the config.json/config.toml file.

I use Doppler Secrets Manager for secrets. I am also use Komodo to deploy, so the `[[COMPOSE_COMMAND]]` value is for Komodo.

```bash
doppler run -- \
  doppler run \
    --mount ./portabase-agent/config.json \
    --mount-template ./portabase-agent/config.json.tmpl \
    --command --command='[[COMPOSE_COMMAND]]'
```