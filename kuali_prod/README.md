## Production-specific Requirements

The two CSS (common security services) accounts, while essentially having the same Network, IAM and overall infrastructure setup, may require some extra or modified steps or state for standing up kuali landscapes and resources. This is an ongoing record of those requirements.



#### S3 buckets

The non-prod account will need to share one or more buckets with the prod account through a [bucket policy](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-policies.html).
This comes with 2 limitations:

1. The prod account will have no access to objects written to the bucket by the non-prod account.
2. The non-prod account will have no access to objects written to the bucket by the prod account.

This is written up in more detail here: [Amazon S3 bucket and object ownership](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-overview.html#about-resource-owner).
The goal is to remove these limitations so that both accounts have equal access to bucket objects, despite ownership.
The following steps are taken to accomplish this:

- Edit Object Ownership policy for the bucket: 

  - BEFORE: "ACLs enabled" w/ "Bucket owner preferred"
  - AFTER: "ACLs disabled" "Bucket owner enforced"

- Apply the following bucket policy *(prod account #:115619461932)* :

  ```
  {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Sid": "AllowProdCommonBucketAccess",
              "Effect": "Allow",
              "Principal": {
                  "AWS": "115619461932"
              },
              "Action": [
                  "s3:DeleteObject*",
                  "s3:GetObject*",
                  "s3:ListBucket",
                  "s3:PutObject*",
                  "s3:Replicate*",
                  "s3:RestoreObject"
              ],
              "Resource": [
                  "arn:aws:s3:::kuali-conf/*",
                  "arn:aws:s3:::kuali-conf"
              ]
          },
          {
              "Sid": "AllowProdEcsTaskExecutionBucketAccess",
              "Effect": "Allow",
              "Principal": {
                  "AWS": "arn:aws:iam::115619461932:role/kuali-ecs-prod-task-execution"
              },
              "Action": [
                  "s3:ListBucket",
                  "s3:GetBucketLocation"
              ],
              "Resource": "arn:aws:s3:::kuali-conf"
          },
          {
              "Sid": "AllowProdEcsTaskExecutionBucketObjectAccess",
              "Effect": "Allow",
              "Principal": {
                  "AWS": "arn:aws:iam::115619461932:role/kuali-ecs-prod-task-execution"
              },
              "Action": [
                  "s3:GetObject",
                  "s3:PutObject"
              ],
              "Resource": "arn:aws:s3:::kuali-conf/*"
          }
      ]
  }
  ```
  
  

#### Secrets

The following secrets were created in the prod account secrets manager service:

- [kuali/prod/kuali-oracle-rds-app-password](https://us-east-1.console.aws.amazon.com/secretsmanager/home?region=us-east-1#!/secret?name=kuali%2Fprod%2Fkuali-oracle-rds-app-password)
- [kuali/prod/kuali-oracle-rds-admin-password](https://us-east-1.console.aws.amazon.com/secretsmanager/home?region=us-east-1#!/secret?name=kuali%2Fprod%2Fkuali-oracle-rds-admin-password)
- [kuali/cor-main/mongodb/connect](https://us-east-1.console.aws.amazon.com/secretsmanager/home?region=us-east-1#!/secret?name=kuali%2Fcor-main%2Fmongodb%2Fconnect)



#### Elastic Container Registry

The prod account needs pull access against the elastic container registry in the non-prod account. To allow this, a resource-based policy is added to each applicable repository in the registry. The global [aws:PrincipalAccount](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-principalaccount) condition is used to filter for the prod account.

```
{
  "Sid": "AllowPull",
  "Effect": "Allow",
  "Principal": "*",
  "Action": [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:DescribeImages",
    "ecr:DescribeRepositories",
    "ecr:GetDownloadUrlForLayer",
    "ecr:ListImages",
    "ecr:ListTagsForResource"
  ],
  "Condition": {
    "ForAnyValue:StringLike": {
      "aws:PrincipalAccount": "115619461932"
    }
  }
}
```



#### Systems Manager
