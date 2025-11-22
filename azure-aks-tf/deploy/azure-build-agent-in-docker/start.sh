#!/bin/bash
set -e

env

if [ -z "${AZP_URL}" ]; then
  echo 1>&2 "error: missing AZP_URL environment variable"
  exit 1
fi

if [ -n "$AZP_CLIENTID" ]; then
  echo "Using service principal credentials to get token"
  az login --allow-no-subscriptions --service-principal --username "$AZP_CLIENTID" --password "$AZP_CLIENTSECRET" --tenant "$AZP_TENANTID"
  # adapted from https://learn.microsoft.com/en-us/azure/databricks/dev-tools/user-aad-token
  AZP_TOKEN=$(az account get-access-token --query accessToken --output tsv)
  echo "Token retrieved"
fi

if [ -z "${AZP_TOKEN_FILE}" ]; then
  if [ -z "${AZP_TOKEN}" ]; then
    echo 1>&2 "error: missing AZP_TOKEN environment variable"
    exit 1
  fi

  AZP_TOKEN_FILE="/azp/.token"
  echo -n "${AZP_TOKEN}" > "${AZP_TOKEN_FILE}"
fi

unset AZP_CLIENTSECRET
# unset AZP_TOKEN

if [ -n "${AZP_WORK}" ]; then
  mkdir -pv "${AZP_WORK}"
fi

cleanup() {
  trap "" EXIT

  if [ -e ./config.sh ]; then
    print_header "Cleanup. Removing Azure Pipelines agent..."

    # If the agent has some running jobs, the configuration removal process will fail.
    # So, give it some time to finish the job.
    while true; do
      ./config.sh remove --unattended --auth "PAT" --token "${AZP_TOKEN}" && break

      echo "Retrying in 30 seconds..."
      sleep 30
    done
  fi
}

print_header() {
  lightcyan="\033[1;36m"
  nocolor="\033[0m"
  echo -e "\n${lightcyan}$1${nocolor}\n"
}

# Let the agent ignore the token env variables
export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

print_header "1. Determining matching Azure Pipelines agent..."

ARCH=$(uname -m)
# Acceptable ARCH: x86, x64, arm, arm64.
if [[ "${ARCH}" == "x86_64" ]]; then ARCH="x64"; fi
echo "# Got architecture '${ARCH}'."

KERNEL=$(uname -s | tr '[:upper:]' '[:lower:]')
# Acceptable KERNEL: linux, linux-musl, osx, rhel.6, win
if [[ "$KERNEL" != "linux" && "$KERNEL" != "linux-musl" && "$KERNEL" != "osx" && "$KERNEL" != "rhel.6" ]];
  then echo "# Your kernel '${KERNEL}', is not supported." && exit 1;
fi
echo "# Got kernel '${KERNEL}'."

TARGETARCH="${KERNEL}-${ARCH}"
# Acceptable TARGETARCH: "linux-arm", "linux-arm64", "linux-musl-arm64", "linux-musl-x64", "linux-x64", "osx-arm64", "osx-x64", "rhel.6-x64", "win-x64", "win-x86"

AZP_AGENT_PACKAGES=$(curl -LsS \
  -u user:"${AZP_TOKEN}" \
  -H "Accept:application/json" \
  "${AZP_URL}/_apis/distributedtask/packages/agent?platform=${TARGETARCH}&top=1")

AZP_AGENT_PACKAGE_LATEST_URL=$(echo "${AZP_AGENT_PACKAGES}" | jq -r ".value[0].downloadUrl")
echo "#   AZP_AGENT_PACKAGE_LATEST_URL=$AZP_AGENT_PACKAGE_LATEST_URL"

if [ -z "${AZP_AGENT_PACKAGE_LATEST_URL}" ] || [ "${AZP_AGENT_PACKAGE_LATEST_URL}" == "null" ]; then
  echo 1>&2 "error: could not determine a matching Azure Pipelines agent"
  echo 1>&2 "check that account ${AZP_URL} is correct and the token is valid for that account"
  exit 1
fi

print_header "2. Downloading and extracting Azure Pipelines agent..."

curl -LsS "${AZP_AGENT_PACKAGE_LATEST_URL}" | tar -xz --checkpoint=1000 & wait $!

# shellcheck disable=SC1091    # Not following: ./env.sh was not specified as input (see shellcheck -x).
source ./env.sh

trap "cleanup; exit 0" EXIT
trap "cleanup; exit 130" INT
trap "cleanup; exit 143" TERM

print_header "3. Configuring Azure Pipelines agent..."
# Query Docker API for the container name, supposing hostname is the container ID.
CONTAINER_NAME=$(docker ps --filter "id=$(hostname)" --format "{{.Names}}" 2>/dev/null)
AZP_AGENT_NAME="${AZP_AGENT_NAME:-$(hostname)}-${CONTAINER_NAME}"
echo "#   AZP_AGENT_NAME=${AZP_AGENT_NAME}"
echo "#   AZP_URL=${AZP_URL}"
echo "#   AZP_TOKEN_FILE=${AZP_TOKEN_FILE}"
echo "#   AZP_POOL=${AZP_POOL:-Default}"
echo "#   AZP_WORK=${AZP_WORK:-_work}"

# Despite it saying "PAT", it can be the token through the service principal
./config.sh --unattended \
  --agent "${AZP_AGENT_NAME}" \
  --url "${AZP_URL}" \
  --auth "PAT" \
  --token "${AZP_TOKEN}" \
  --pool "${AZP_POOL:-Default}" \
  --work "${AZP_WORK:-_work}" \
  --replace \
  --acceptTeeEula & wait $!

print_header "4. Running Azure Pipelines agent..."

chmod +x ./run.sh

# To be aware of TERM and INT signals call ./run.sh
# Running it with the --once flag at the end will shut down the agent after the build is executed
./run.sh "$@" & wait $!
