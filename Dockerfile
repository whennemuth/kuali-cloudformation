FROM amazonlinux AS BASELINE

ARG GIT_HTTP=https://github.com/bu-ist/kuali-infrastructure.git
ARG GIT_SSH=git@github.com:bu-ist/kuali-infrastructure.git
ARG GIT_USERNAME
ARG SECRETS_SERVICE=secrets

WORKDIR /

# Install simple utilities
RUN \
  yum install -y git zip unzip tar jq && \
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
  unzip awscliv2.zip && \
  ./aws/install

# Install node and npm
RUN \
  # Install node
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.34.0/install.sh | bash && \
  . $HOME/.nvm/nvm.sh && \
  nvm install node && \
  \
  # For some reason, nvm may not create symlinks to npm and/or node, so check and correct if necessary.
  if [ -z "$(ls -1 /usr/bin | grep 'npm')" ] ; then \
    echo "Symlink for npm wasn't created by nvm during install, creating now..." && \
    ln -s $(find /.nvm -type f -iname npm-cli.js) /usr/bin/npm; \
  fi && \
  if [ -z "$(ls -1 /usr/bin | grep 'node')" ] ; then \
    echo "Symlink for node wasn't created by nvm during install, creating now..." && \
    ln -s $(find /.nvm -type f -iname node) /usr/bin/node; \
  fi && \
  echo "npm version: $(sh -c 'npm --version')" && \
  echo "node version: $(sh -c 'node --version')"

# Download the git repository. Keys are curled in from a container running in parallel at the time of this build.
RUN \
  curl http://${SECRETS_SERVICE}/rsa -o rsa && \
  if [ -f rsa ] && [ -z "$(cat rsa | grep -i '404 not found')" ] ; then \
    chmod 600 rsa && \
    eval `ssh-agent -s` && \
    ssh-add rsa && \
    ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts && \
    echo "Github ssh key obtained, pulling from ${GIT_SSH}" && \
    git clone $GIT_SSH && \
    eval `ssh-agent -k` && \
    rm rsa; \
  else \
    curl -f http://${SECRETS_SERVICE}/token -o token && \
    echo "Personal access token obtained, pulling from $(echo ${GIT_HTTP} | sed 's|github.com|'${GIT_USERNAME}:[token]'@\0|')..." && \
    gitRepo=$(echo ${GIT_HTTP} | sed 's|github.com|'${GIT_USERNAME}:$(cat token)'@\0|') && \
    git clone $gitRepo && \
    rm token; \
  fi

  CMD [ "sh" "-c" "cd /kuali-infrastructure && sh docker.sh test" ]
