## Kuali migration to RDS

Migrate existing Kuali oracle databases to empty oracle RDS instance(s).
The [AWS Database Migration Service](https://docs.aws.amazon.com/dms/latest/userguide/Welcome.html) is used here to migrate data from source kuali oracle databases into new target RDS instances.

#### Migration Types:

- **Homogenous:** The source and target databases share the same database engine (oracle). AWS refers to this as a "homogenous" migration.
  Technically, for a homogenous migration, the service can automatically create schemas, tables, indexes, and views while it is migrating. 
- **Heterogenous:** When the database engines of source and target differ (ie: oracle to mysql) you would create the schemas first using the [AWS Schema Conversion tool](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html). After that you would start using the migration service.

Currently we are sticking with oracle and only need to perform a homogenous migration.
However, the documentation states that the migration service does not auto-create all database objects.

> ”DMS takes a minimalist approach and creates only those objects required to efficiently migrate the data. In other words, AWS DMS creates tables, primary keys, and in some cases unique indexes, but doesn’t create any other objects that are not required to efficiently migrate the data from the source. For example, it doesn’t create secondary indexes, non primary key constraints, or data defaults”.

So, to be thorough, the [AWS Schema Conversion tool](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Welcome.html) is used anyway.

*(NOTE: In a later phase, we will want to target using mysql, in which case the conversion tool is essential)*

### Steps:

1. **Read the documentation:**
   Read amazons user guide that covers what's being done in the following steps: [Converting Oracle to Amazon RDS for Oracle](https://docs.aws.amazon.com/SchemaConversionTool/latest/userguide/CHAP_Source.Oracle.ToRDSOracle.html)

5. **Kuali Schema creation**
   Use the schema conversion tool to create the schema(s)
   [Instructions...](sct/README.md)

6. **Kuali Data Migration**
   Create a small database migration stack with cloud formation and run it.
   [Instructions...](dms/README.md)


