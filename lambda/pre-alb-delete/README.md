## Kuali Web Application Firewall

A stack delete operation will fail if any logging has been enabled for the ALB or WAF.
Cloudformation will not delete s3 buckets with contents in them - the stack delete operation will fail if they do.
The AWS CLI can be used as part of bash operation that issues the stack command to first empty the buckets that receive the logging.
However, after being emptied, these buckets continue to receive logging that occurs until the ALB and WAF resources themselves are deleted.
The related s3 buckets still fail to get deleted since they took on additional content in this small time window and the stack operation fails.
Therefore, you must also disable logging for the ALB and WAF. This lambda function does both (disables logging and empties buckets).
*NOTE: Logging disablement and bucket clearing could be both be done with the cli, though such scripting is starting to pile up.*