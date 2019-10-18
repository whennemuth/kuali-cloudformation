## CREATE DUMMY DOCKER IMAGES

Create docker images from which you can run containers that use node and express to serve up landing pages that look like the kuali-research and kuali coi applications.

All this functionality is driven by the docker.sh bash script file.

```
USAGE: sh docker.sh [OPTIONS]

  Options:

    --task    What docker task is to be performed?
                "build":   Build the docker image
                "rebuild": Build the docker image without using the cache (builds from scratch) 
                "run":     Run the docker container
                "rerun":   Build the docker image AND run the container
                "publish": Tag the last built docker image indicated by the --service arg and push to dockerhub
    --service What application is being built/run (kc|coi)
    --ssl     Build the image so it will have certs/keys and force redirect to ssl
    --help    Print out this usage readout.
```

EXAMPLES:

```
# Build the docker image for kuali research
sh docker.sh --task build --service kc

# Build the docker image for kuali coi and run it so it can be accessed through https:
sh docker.sh --task rerun --service coi --ssl

# Publish both images to the public wrh1 dockerhub registry
sh docker.sh --task publish --service kc && \
sh docker.sh --task publish --service coi
```

NOTES:

- Currently the tag that is use when publishing to the registry is hard-coded to "1906.0021"
- Currently Using my own "wrh1" public dockerhub repository.
- You can run the https containers locally (kc:localhost:8080, coi:localhost:8082), but for the ECS cluster, it may not be necessary as the AWS::ElasticLoadBalancingV2::ListenerRule will take care of the 443 traffic - dont' know yet.