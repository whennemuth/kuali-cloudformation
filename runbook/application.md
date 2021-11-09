## Application Migration:

After the database has been migrated and tested, the kuali research application stack itself needs to be cloudformed as an ecs cluster.
The before and after picture of the application migration will look something like this:

![](C:\whennemuth\workspaces\ecs_workspace\cloud-formation\kuali-infrastructure\runbook\application.png)

There is more [detailed documentation for ECS stack creation](../kuali_ecs/README.md).
However, the exact command for building a stack is as follows:

- **Staging**
  Ensure an SSL certificate is in ACM first.

  ```
  sh main.sh create-stack landscape=stg using_route53=true create_waf=true enable_alb_logging=true
  ```

- **Production**
  Ensure an SSL certificate is in ACM first.

  ```
  sh main.sh create-stack landscape=prod using_route53=true create_waf=true enable_alb_logging=true
  ```

  

