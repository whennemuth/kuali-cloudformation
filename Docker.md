## Dockerize this repository

#### Requirements

- Bash
- Docker
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- [Session Manager plugin for the AWS CLI](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

#### Problem

Technically, if you clone this repository you should be able to run the commands without issues:

- On any linux system with /bin/bash
- On Windows with git bash

However, there may be problems on OSX, which probably uses bash version 3:

- `declare -A` (associative arrays) are a bash 4+ feature and the mac may have 3.X of bash installed, depending on the OSX version
- The bash scripts call out to other utilities, like grep, which on OSX may not support Perl-style regex expressions
- Parameter expansion for lower or uppercasing will not work for bash 3.X
- etc...

#### Solution

One of the primary uses of docker is to eliminate platform dependency.
To achieve this, we wrap this codebase into a docker image based on linux, and it's various commands can be issued to containers run from it.

The steps below detail how to bring the source code in this part of the git repo to running docker container.
Skip to step 3 if the docker image is already available in a docker registry somewhere

1. ##### [Optional] Make the docker image available to others

   If you can already have access to a docker registry with the image, you can skip to step 3.
   If you need the image or need to make it available for others, follow these steps:

   1. ##### Build the docker image

      ```
      git clone https://github.com/bu-ist/kuali-infrastructure.git
      cd kuali-infrastructure
      mkdir secrets
      # Place into the secrets directory either the ssh key you use for the repo, or a file containing a personal access token for the repo
      sh docker.sh build
      ```

      The Dockerfile has `RUN` instructions to simply clone https://github.com/bu-ist/kuali-infrastructure.git again, now as part of the image.
      However, we will not be using simple passwords (due to be obsolete soon), so the ssh key or personal access token is used.
      This is done by mounting the key/token to another container that runs an http server. The docker build curls in the key/token and uses it to authenticate for the git clone. This is done so that there is no residual sign of the key/token in any image layer or log that would be present if the key/token were to be acquired using the `COPY` instruction, or passed in through the `-e` or `--build-arg` command line options.

      *See: [docker build with private credentials — the issue with intermediate layer secrets](https://medium.com/@activenode/docker-build-with-private-credentials-the-issue-with-intermediate-layer-secrets-7cdb370c726a)*

   2. ##### Push the docker image

      ```
      # Assumes dockerhub is the registry and the repository name is "myrepo"
      docker login -u myrepo -p mypassword
      docker tag kuali-infrastructure myrepo/kuali-infrastructure
      docker push myrepo/kuali-infrastructrue
      ```

2. ##### Run the docker container

   Containerized use of this repository assumes you are only running cloud-formation templates and scripts therein.
   However, the editing would be made against files in a clone of this repository only involving docker when the container is run which accesses the modified files through a bind mount to the cloned repository. 

   You run the container passing the same commands that are documented throughout the repository.
   For example, to create a new ecs stack, the raw command would be as follows:

   ```
   cd kuali_ecs
   sh main.sh create-stack \
       deep_validation=false \
       landscape=MyLandscape \
       baseline=qa \
       rds_landscape_to_clone=ci \
       using_route53=true \
       create_mongo=true \
       using_shibboleth=true
   ```

    Running this same command with the container would look like this:

   ```
   docker run \
     --rm \
     -v $HOME/.aws:/root/.aws \
     -v /path/to/this/repo/kuali-infrastructure:kuali-infrastructure \
     kuali-infrastructure \
       sh main.sh create-stack \
         deep_validation=false \
         landscape=MyLandscape \
         baseline=qa \
         rds_landscape_to_clone=ci \
         using_route53=true \
         create_mongo=true \
         using_shibboleth=true
   ```

   ##### Run the container for a tunnel to a private RDS database

   You may need to connect to an RDS database running in a private subnet in the cloud account.
   A jumpbox will have already been setup to proxy an ssh connection via ssm service: 

   ```
   # Assumes the docker registry is public and no login is required.
   source <(docker run --rm -v $HOME/.aws:/root/.aws bostonuniversity/kuali-infrastructure tunnel landscape=ci) ssm
   ```

   To explain what's going on here:
   The image is run briefly as a container and it outputs some script and exits.
   This output script is sourced so as to be run in the current shell.
   What this script does is use the available aws cli to open a tunnel to the RDS instance.

   
