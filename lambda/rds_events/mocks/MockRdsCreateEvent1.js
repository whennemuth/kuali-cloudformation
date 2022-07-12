module.exports = {
  version: "0",
  id: "68f6e973-1a0c-d37b-f2f2-94a7f62ffd4e",
  "detail-type": "RDS DB Instance Event",
  source: "aws.rds",
  account: "770203350335",
  time: "2022-06-27T22:36:43Z",
  region: "us-east-1",
  resources: [
    "arn:aws:rds:us-east-1:770203350335:db:kuali-oracle-stg"
  ],
  detail: {
    EventCategories: [
      "creation"
    ],
    SourceType: "DB_INSTANCE",
    SourceArn: "arn:aws:rds:us-east-1:770203350335:db:kuali-oracle-stg",
    Date: "2022-06-27T22:36:43.292Z",
    Message: "DB instance created.",
    SourceIdentifier: "rds:kuali-oracle-stg",
    EventID: "RDS-EVENT-0005"
  }
};
