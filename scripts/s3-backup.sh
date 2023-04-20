#!/bin/bash

sourceProfile="legacy"
sourceAccountNbr="$(aws --profile=${sourceProfile} sts get-caller-identity 2> /dev/null | jq -r '.Account')"
echo "Source account number: $sourceAccountNbr"

targetProfile="infnprd"
targetAccountNbr="$(aws --profile=${targetProfile} sts get-caller-identity 2> /dev/null | jq -r '.Account')"
echo "Target account number: $targetAccountNbr"
targetCanonicalAccountId="$(aws --profile=${targetProfile} s3api list-buckets --query Owner.ID --output text)"
targetBucketName="kuali-legacy-backups"

username="kuali-legacy-s3-backup-user"
userPolicyName="kuali-legacy-s3-backup-policy"
userRoleName="kuali-legacy-s3-backup-role"
userProfile="legacy-backup"
userProfileTemp="legacy-backup-temp"

region="us-east-1"

createUser() {
  aws --profile=$targetProfile iam create-user --user-name $username
}

createUserProfile() {
  local json="$(aws --profile=$targetProfile iam create-access-key --user-name $username)"
  [ $? -gt 0 ] && return 1
  echo "$username access key created"
  echo "" >> ~/.aws/credentials
  echo "[${userProfile}]" >> ~/.aws/credentials
  echo "region = $region" >> ~/.aws/credentials
  echo "aws_access_key_id = $(echo "$json" | jq -r '.AccessKey.AccessKeyId')" >> ~/.aws/credentials
  echo "aws_secret_access_key = $(echo "$json" | jq -r '.AccessKey.SecretAccessKey')" >> ~/.aws/credentials
  echo "$userProfile created"
}

createUserBucketAccessRole() {
  aws --profile=$targetProfile iam create-role \
    --role-name ${userRoleName} \
    --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": "arn:aws:iam::'${targetAccountNbr}':user/'${username}'"
                    },
                    "Action": "sts:AssumeRole",
                    "Condition": {}
                }
            ]
        }'    
}

createUserBucketAccessPolicy() {
  echo 'policy.json' >> .gitignore

  cat <<EOF > policy.json 
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject"
            ],
            "Resource": [
              $(
                first=''
                for sourceBucket in $(aws --profile=$sourceProfile s3 ls | cut -d" " -f3 | sed 's/\n//g') ; do
                  echo "               $first\"arn:aws:s3:::${sourceBucket}\","
                  echo "               \"arn:aws:s3:::${sourceBucket}/*\""
                  first=','
                done
              )
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": [
                "arn:aws:s3:::${targetBucketName}",
                "arn:aws:s3:::${targetBucketName}/*"
            ]
        }
    ]    
  }
EOF

  aws --profile=$targetProfile iam create-policy \
    --policy-name $userPolicyName \
    --policy-document file://./policy.json
}

attachUserBucketAccessPolicy() {
  aws --profile=$targetProfile iam attach-role-policy \
    --role-name ${userRoleName} \
    --policy-arn arn:aws:iam::${targetAccountNbr}:policy/$userPolicyName
}

# Add a policy to a specified bucket that grants a specified role in a specified account access to read and list from it.
addBucketPolicy() {
  local profile="$1"
  local bucket="$2"
  local acct="$3"
  local role="$4"

  echo "Adding bucket policy to ${bucket}..."
  aws --profile=$profile s3api put-bucket-policy --bucket $bucket --policy '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {"AWS": "arn:aws:iam::'${acct}':role/'${role}'"},
            "Action": ["s3:*"],
            "Resource": [
                "arn:aws:s3:::'${bucket}'/*",
                "arn:aws:s3:::'${bucket}'"
            ]
        }
    ]}'
}

addPoliciesToSourceBuckets() {
  for sourceBucket in $(aws --profile=$sourceProfile s3 ls | cut -d' ' -f3) ; do
    sourceBucket="$(echo $sourceBucket | dos2unix)"
    addBucketPolicy \
      "$sourceProfile" \
      "$sourceBucket" \
      "$targetAccountNbr" \
      "$userRoleName"
    [ $? -gt 0 ] && return 1
  done
}

# The objects in a bucket that were uploaded from another account are owned by that account.
# This means that our users role will still not have access to perform getObject and listObject
# One way around this is to recursively apply full control to the bucket owner, which is this account.
addAclsToForeignOwnedBucketObjects() {
  local profile="$1"
  local bucket="$2"
  aws --profile=$profile s3 cp --recursive --acl bucket-owner-full-control s3://$bucket s3://$bucket --metadata-directive REPLACE
}

setup() {
  createUser \
  && \
  createUserProfile \
  && \
  createUserBucketAccessRole \
  && \
  createUserBucketAccessPolicy \
  && \
  attachUserBucketAccessPolicy \
  && \
  addPoliciesToSourceBuckets
}

assumeRole() {
  local json="$(aws --profile=$userProfile sts assume-role \
    --role-arn "arn:aws:iam::${targetAccountNbr}:role/$userRoleName" \
    --role-session-name kuali-legacy-s3-backup-session
    --duration-seconds 28800)"
  [ $? -gt 0 ] && return 1
  echo "$$userRoleName assumed"
  echo "" >> ~/.aws/credentials
  echo "[${userProfileTemp}]" >> ~/.aws/credentials
  echo "region = $region" >> ~/.aws/credentials
  echo "aws_access_key_id = $(echo "$json" | jq -r '.Credentials.AccessKeyId')" >> ~/.aws/credentials
  echo "aws_secret_access_key = $(echo "$json" | jq -r '.Credentials.SecretAccessKey')" >> ~/.aws/credentials
  echo "aws_session_token = $(echo "$json" | jq -r '.Credentials.SessionToken')" >> ~/.aws/credentials
  echo "$userProfileTemp created"

  aws --profile=$userProfileTemp s3 ls s3://730096353738-dlt-utilization
}

copy() {
  local bucket="$1"
  aws --profile=$userProfileTemp s3 sync s3://$bucket  s3://${targetBucketName}/${bucket} --source-region $region --region $region
}

copyAll() {
  for sourceBucket in $(aws --profile=$sourceProfile s3 ls | cut -d' ' -f3) ; do
    sourceBucket="$(echo $sourceBucket | dos2unix)"
    copy $sourceBucket
  done
}

ftn=$1

shift

if [ -z "$ftn" ] ; then
  setup && assumeRole && copy
else
  echo "$ftn $@"
  eval "$ftn $@"
fi