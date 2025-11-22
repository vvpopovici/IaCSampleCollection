# DESCRIPTION

- Here are files to build a Docker Image to serve as Azure DevOps Build agent.
- Commands works well in PowerShell.
- Generate a Personal Access Token here [Personal access tokens](https://dev.azure.com/vvp-vvproj/_usersSettings/tokens).

## Build and Run the agent

### One agent (docker run)

```bash
cd ./deploy/azure-build-agent-in-docker/

# Prepare the field: .env
cp .env.tempate .env
# --- Update .env file with your data.

# Build Docker Image.
docker build ./ -t agent --progress=plain

# Run agent on your localhost.
docker run --rm -it --name agent -v //var/run/docker.sock:/var/run/docker.sock --privileged --network host --env-file .env agent

# Press <Ctrl+C> to stop the agent after all pipelines' jobs finished.
```

### One or more agent (docker compose up)

```bash
cd ./deploy/azure-build-agent-in-docker/

# Prepare the field: .env
cp .env.tempate .env
# --- Update .env file with your data.

# Build Docker Image.
docker compose build --progress=plain

docker compose up

# Press <Ctrl+C> to stop the agent after all pipelines' jobs finished.

# Stop and remove all containers
docker compose down
```
