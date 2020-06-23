    aws \
      cloudformation update-stack \
      --stack-name kuali-ecs \
      --no-use-previous-template \
      --template-url https://s3.amazonaws.com/kuali-research-ec2-setup/cloudformation/kuali_ecs/main.yaml \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
      --parameters '[
        {
          "ParameterKey" : "CertificateArn",
          "ParameterValue" : "arn:aws:iam::730096353738:server-certificate/kuali-ecs-cert"
        }
        ,{
          "ParameterKey" : "KcImage",
          "ParameterValue" : "730096353738.dkr.ecr.us-east-1.amazonaws.com/coeus-sandbox:2001.0040"
        }
        ,{
          "ParameterKey" : "CoreImage",
          "ParameterValue" : "730096353738.dkr.ecr.us-east-1.amazonaws.com/core:2001.0040"
        }
        ,{
          "ParameterKey" : "PortalImage",
          "ParameterValue" : "730096353738.dkr.ecr.us-east-1.amazonaws.com/portal:2001.0040"
        }
        ,{
          "ParameterKey" : "PdfImage",
          "ParameterValue" : "730096353738.dkr.ecr.us-east-1.amazonaws.com/research-pdf:2002.0003"
        }
        ,{
          "ParameterKey" : "Landscape",
          "ParameterValue" : "sb"
        }
        ,{
          "ParameterKey" : "GlobalTag",
          "ParameterValue" : "kuali-ecs"
        }
        ,{
          "ParameterKey" : "BucketName",
          "ParameterValue" : "kuali-research-ec2-setup"
        }
      ]'
