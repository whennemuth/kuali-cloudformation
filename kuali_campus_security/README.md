## Kuali Security Group

This stack concerns itself with creating a single security group.
This is a centralized security group creation for resources (like databases) that require ingress restrictions consistent with "private" subnets in a common services account VPC.
This involves reducing CIDR ingress down from campus vpn-wide to just the ip addresses of clients out on the network who are in a "need to know" category. This category includes:

- SAPBW.
  SAP staff require direct access to the kuali oracle database from their own servers for a series of views.
- Informatica
  These servers run nightly ETL jobs that required direct access to the kuali oracle database
- Developers
  Anyone running a database client like sqldeveloper, will need direct access to the kuali oracle database.
  So as not to expose the databases to the entire campus network, developers must log in to the VPN through the "dbreport" subgroup.

 The security group is built with ingress rules that restrict access to the IP ranges and individual IP addresses of these database consumers.

**How to run:**

This is intended as a nested stack.
For an example of use in a parent stack see the [rds oracle stack template](../kuali_rds/rds-oracle.yaml)