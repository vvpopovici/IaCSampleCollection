# Consult the article https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/docker?view=azure-devops

FROM ubuntu:22.04

LABEL MAINTAINER="VVP"
LABEL MAINTAINER_EMAIL="vasile.popovici@vvp.com"
LABEL DESCRIPTION="This builds a Docker Image to be used as Build Agent in Azure DevOps."

ENV DEBIAN_FRONTEND="noninteractive"

RUN apt-get -qq update && apt-get -qqy install --no-install-recommends \
    jq git unzip dos2unix openjdk-17-jdk curl \
  && apt-get -qqy autoremove && apt-get -qqy clean && rm -rf /var/lib/{apt,dpkg,cache,log}/

WORKDIR /azp/

HEALTHCHECK --interval=60s --timeout=15s --start-period=15s --retries=3 CMD ps aux | grep -q /azp/bin/Agent.Listener

# Git version 2.35.2 introduces security fix that breaks action\checkout https://github.com/actions/checkout/issues/760
COPY gitconfig.template /etc/gitconfig

COPY ./start.sh /azp/
RUN dos2unix /azp/start.sh && chmod +x /azp/start.sh

# Copy Dockerfile into container to have the possibility to decide if the image has to be rebuilt or not.
# The decision may be taken (it's on you to implement) by comparing the current Dockerfile (from repo) with the one in the image.
# So, if any differences, rebuild is required.
COPY ./Dockerfile /

# Install Azure CLI (instructions taken from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
RUN apt-get -qq update && apt-get -qqy install --no-install-recommends \
    python3 python3-dev python3-pip python3-venv curl \
  && curl -fsSL https://aka.ms/InstallAzureCLIDeb | bash \
  && az bicep install \
  && apt-get -qqy autoremove && apt-get -qqy clean && rm -rf /var/lib/{apt,dpkg,cache,log}/

RUN curl -L https://aka.ms/downloadazcopy-v10-linux -o ./azcopy.tar.gz \
  && tar -xvf ./azcopy.tar.gz \
  && mv -v azcopy_*/* /usr/local/bin/ \
  && rm -rfv ./azcopy*

# Install Bicep CLI (instructions taken from https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install#linux)
# Acceptable values for ARCH=arm64|musl-x64|x64|arm64 (uname -m)
RUN bash -c 'export ARCH=$(if [[ $(uname -m | grep "x86_64\|aarch64") ]]; then echo "x64"; else uname -m; fi) \
  && curl -L https://github.com/Azure/bicep/releases/latest/download/bicep-linux-${ARCH} -o ./bicep' \
  && chmod +x ./bicep \
  && mv ./bicep /usr/local/bin/bicep -f

# Install Docker CLI
RUN apt-get -qq update && apt-get -qqy install --no-install-recommends \
    ca-certificates curl \
  && install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${VERSION_CODENAME}) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
  && apt-get -qq update && apt-get -qqy install --no-install-recommends \
    docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  && apt-get -qqy autoremove && apt-get -qqy clean && rm -rf /var/lib/{apt,dpkg,cache,log}/

# Install DotNet, https://dotnet.microsoft.com/en-us/download/dotnet
ENV DOTNET_VERSION="8.0"
RUN apt-get -qq update && apt-get -qqy install --no-install-recommends \
    wget apt-transport-https software-properties-common \
  && wget -q --progress=bar:force:noscroll https://packages.microsoft.com/config/ubuntu/$(. /etc/os-release && echo ${VERSION_ID})/packages-microsoft-prod.deb \
  && dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb \
  && apt-get -qq update && apt-get -qqy install --no-install-recommends \
    dotnet-sdk-${DOTNET_VERSION} \
  && apt-get -qqy autoremove && apt-get -qqy clean && rm -rf /var/lib/{apt,dpkg,cache,log}/

# Install PowerShell, https://github.com/PowerShell/PowerShell/releases
ENV POWERSHELL_VERSION="7.5.2"
RUN curl -fsSL https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell_${POWERSHELL_VERSION}-1.deb_amd64.deb -o /tmp/powershell.deb \
  && dpkg -i /tmp/powershell.deb \
  && apt-get install -f \
  && rm /tmp/powershell.deb

# Install PowerShell module Az version
RUN pwsh -c "Install-Module -Name Az, Microsoft.Graph -Scope AllUsers -Repository PSGallery -Force -Verbose"

# Install NodeJs, https://nodejs.org/en/download/package-manager
ENV NODEJS_VERSION=18
RUN apt-get -qq update && apt-get -qqy install --no-install-recommends \
    curl \
  && curl -fsSL https://deb.nodesource.com/setup_${NODEJS_VERSION}.x -o /tmp/nodesource_setup.sh \
  && bash /tmp/nodesource_setup.sh \
  && apt-get -qqy install nodejs \
  && apt-get -qqy autoremove && apt-get -qqy clean && rm -rf /var/lib/{apt,dpkg,cache,log}/

# Install Terraform, https://developer.hashicorp.com/terraform/install#linux
RUN apt-get -qq update && apt-get -qqy install --no-install-recommends \
  wget \
  && wget -O - https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
  && apt-get -qqy update \
  && apt-get -qqy install terraform \
  && apt-get -qqy autoremove && apt-get -qqy clean && rm -rf /var/lib/{apt,dpkg,cache,log}/

# Install Kubectl, https://v1-32.docs.kubernetes.io/docs/tasks/tools/install-kubectl-linux/
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl -v \
  && az aks install-cli

# Install Helm, https://helm.sh/docs/intro/install/#from-apt-debianubuntu, https://github.com/helm/helm/releases/latest
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install reqs for Azure DevOps Agent
RUN apt-get -qq update && apt-get -qqy upgrade && apt-get -qqy install --no-install-recommends \
    curl git jq libicu70 \
  && apt-get -qqy autoremove && apt-get -qqy clean && rm -rf /var/lib/{apt,dpkg,cache,log}/

# Create agent user and set up home directory
RUN useradd -m -d /home/agent agent
RUN chown -R agent:agent /azp /home/agent
# Next command is to avoid sudo for for Docker CLI usage
RUN usermod -aG systemd-journal agent

USER agent

CMD [ "./start.sh" ]
