    aws \
      cloudformation create-stack \
      --stack-name kuali-ec2-alb \
       \
      --template-url https://s3.amazonaws.com/kuali-research-ec2-setup/cloudformation/kuali_ec2_alb/main-create-subnets.yaml \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
      --parameters '[
        {
          "ParameterKey" : "VpcId",
          "ParameterValue" : "vpc-75d00612"
        }
        ,{
          "ParameterKey" : "InternetGatewayId",
          "ParameterValue" : "igw-6997e90d"
        }
        ,{
          "ParameterKey" : "CertificateArn",
          "ParameterValue" : "arn:aws:iam::730096353738:server-certificate/kuali-ec2-alb-cert"
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
          "ParameterValue" : "kuali-ec2-alb"
        }
        ,{
          "ParameterKey" : "BucketName",
          "ParameterValue" : "kuali-research-ec2-setup"
        }
      ]'
