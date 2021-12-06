## Jenkins build & CI/CD server for Kuali research

<img align="left" src="jenkins1.png" alt="jenkins1" style="zoom:25%; margin-right:50px;" />Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo. Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt ut labore et dolore magnam aliquam quaerat voluptatem. Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur? Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur, vel illum qui dolorem eum fugiat quo voluptas nulla pariatur?

```
cd kuali_jenkins

# Create a jenkins server, giving it a size down from the default xlarge.
sh main.sh create-stack stack_name=kuali-jenkins2 global_tag=kuali-jenkins2 ec2_instance_type=m5.large

# Now you redecide that you want xlarge, and you don't need to upload changes to any bash scripts, so use:
sh main.sh recreate-stack stack_name=kuali-jenkins2 global_tag=kuali-jenkins2 ec2_instance_type=m5.xlarge s3_refresh=false
```

