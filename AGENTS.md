# Machine Setup Automation

Automation scripts for installing and configuring a 

## Core Facts
- docker based deployment
  - setup scripts generate `docker-compose.yml` for each service
- ufw as used as firewall on the ubuntu host
- traefik as reverse proxy
  - integration examples: [setup-forgejo.sh](tasks/setup-forgejo.sh) and [setup-openwebui.sh](tasks/setup-openwebui.sh)
- target service data base directory: `/srv` , e.g. for forgejo: `/srv/forgejo`

## Instructions
ALWAYS lint created or modified files with the following tools:

- bash files (`.sh`) -> use `shellcheck`
- `.yml` -> use `yamllint`
- json (`.js`, `.json`) -> use `jq`
- `Dockerfile` -> use hadolint via executing: docker run --rm -i hadolint/hadolint < Dockerfile