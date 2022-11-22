module.exports = {
  version: "0",
  id: "36f4afa3-1d4a-15cf-af45-032afa2994be",
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
                                  groupId: "sg-000537769a1c2d858",
                                  description: "Allows ingress to an rds instance created in another stack from application ec2 instances created in this stack."
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
          requestId: "b389022f-eb12-4752-a925-f12a129d8d29",
          _return: true,
          securityGroupRuleSet: {
              items: [
                  {
                      groupOwnerId: "770203350335",
                      groupId: "sg-01f414f5313452cd1",
                      securityGroupRuleId: "sgr-02e2ca7d55820dc26",
                      description: "Allows ingress to an rds instance created in another stack from application ec2 instances created in this stack.",
                      isEgress: false,
                      ipProtocol: "tcp",
                      fromPort: 1521,
                      toPort: 1521,
                      referencedGroupInfo: {
                          userId: "770203350335",
                          groupId: "sg-000537769a1c2d858"
                      }
                  }
              ]
          }
      },
      requestID: "b389022f-eb12-4752-a925-f12a129d8d29",
      eventID: "50dd3491-f4bc-4a04-a4e0-db6d5311049d",
      readOnly: false,
      eventType: "AwsApiCall",
      managementEvent: true,
      recipientAccountId: "770203350335",
      eventCategory: "Management",
      sessionCredentialFromConsole: "true"
  }
}