## Jenkins build & CI/CD server for Kuali research

<img align="left" src="jenkins1.png" alt="jenkins1" style="zoom:25%; margin-right:100px;" />Jenkins is a build automation and deployment server for CI/CD pipelines. It is essentially comprised of a collection of jobs and triggers. Among the jobs performed for Kuali are:

------

- Pulling source code from github and building the java application for the research app
- Packaging the build artifact into docker images and exporting them to an elastic container registry.
- Performing the same steps for the other kuali service (cor-main, dashboard, pdf, reverse-proxy)
- Building application infrastructure server/cluster stacks in cloudformation, each drawing from the docker registry.

------



```
cd kuali_jenkins

# Create a jenkins server, giving it a size down from the default xlarge.
sh main.sh create-stack stack_name=kuali-jenkins2 global_tag=kuali-jenkins2 ec2_instance_type=m5.large

# Now you redecide that you want xlarge, and you don't need to upload changes to any bash scripts, so use:
sh main.sh recreate-stack stack_name=kuali-jenkins2 global_tag=kuali-jenkins2 ec2_instance_type=m5.xlarge s3_refresh=false
```

