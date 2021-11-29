```
cd kuali_jenkins

# Create a jenkins server, giving it a size down from the default xlarge.
sh main.sh create-stack stack_name=kuali-jenkins2 global_tag=kuali-jenkins2 ec2_instance_type=m5.large

# Now you redecide that you want xlarge, and you don't need to upload changes to any bash scripts, so use:
sh main.sh recreate-stack stack_name=kuali-jenkins2 global_tag=kuali-jenkins2 ec2_instance_type=m5.large s3_refresh=false
```

