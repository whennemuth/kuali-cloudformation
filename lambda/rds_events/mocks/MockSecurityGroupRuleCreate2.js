module.exports = {
  version: "0",
  id: "7400a4bd-d520-3e73-7dd9-beffc1e29501",
  "detail-type": "AWS API Call via CloudTrail",
  source: "aws.ec2",
  account: "770203350335",
  time: "2022-11-16T02:34:24Z",
  region: "us-east-1",
  resources: [],
  detail: {
      eventVersion: "1.08",
      userIdentity: {
          type: "AssumedRole",
          principalId: "AROA3GU5SOU7SMTVU2WWV:wrh@bu.edu",
          arn: "arn:aws:sts::770203350335:assumed-role/Shibboleth-InfraMgt/wrh@bu.edu",
          accountId: "770203350335",
          sessionContext: {
              sessionIssuer: {
                  type: "Role",
                  principalId: "AROA3GU5SOU7SMTVU2WWV",
                  arn: "arn:aws:iam::770203350335:role/Shibboleth-InfraMgt",
                  accountId: "770203350335",
                  userName: "Shibboleth-InfraMgt"
              },
              webIdFederationData: {},
              attributes: {
                  creationDate: "2022-11-16T02:04:12Z",
                  mfaAuthenticated: "false"
              }
          },
          invokedBy: "cloudformation.amazonaws.com"
      },
      eventTime: "2022-11-16T02:34:24Z",
      eventSource: "ec2.amazonaws.com",
      eventName: "AuthorizeSecurityGroupIngress",
      awsRegion: "us-east-1",
      sourceIPAddress: "AWS Internal",
      userAgent: "AWS Internal",
      requestParameters: {
          groupId: "sg-01f414f5313452cd1",
          ipPermissions: {
              items: [
                  {
                      ipProtocol: "tcp",
                      fromPort: 1521,
                      toPort: 1521,
                      groups: {
                          items: [
                              {
                                  groupId: "sg-0e4d6b8a99395a608",
                                  description: "Allows ingress to an rds instance created in another stack from the alb created in this stack."
                              }
                          ]
                      },
                      ipRanges: {},
                      ipv6Ranges: {},
                      prefixListIds: {}
                  }
              ]
          }
      },
      responseElements: {
          requestId: "7fcdb9af-59ef-4a6b-a3b2-3a7956005628",
          _return: true,
          securityGroupRuleSet: {
              items: [
                  {
                      groupOwnerId: "770203350335",
                      groupId: "sg-01f414f5313452cd1",
                      securityGroupRuleId: "sgr-052f232f61106d4c4",
                      description: "Allows ingress to an rds instance created in another stack from the alb created in this stack.",
                      isEgress: false,
                      ipProtocol: "tcp",
                      fromPort: 1521,
                      toPort: 1521,
                      referencedGroupInfo: {
                          userId: "770203350335",
                          groupId: "sg-0e4d6b8a99395a608"
                      }
                  }
              ]
          }
      },
      requestID: "7fcdb9af-59ef-4a6b-a3b2-3a7956005628",
      eventID: "1091b24b-5b58-4010-a065-4fd069c06872",
      readOnly: false,
      eventType: "AwsApiCall",
      managementEvent: true,
      recipientAccountId: "770203350335",
      eventCategory: "Management",
      sessionCredentialFromConsole: "true"
  }
}