## TESTING RUNBOOK

#### <img align="left" src="C:\whennemuth\workspaces\ecs_workspace\cloud-formation\kuali-infrastructure\runbook\checklist-test.png">Kuali Research mock migration release testing.

This is the sequencing of work and assignments that will go into transitioning the staging kuali research application environment stack to the common security services (CSS) account for testing in that new account.

No functional changes are made to the app itself, but the "change of address",  and other differences (database, load balancer, ECS, firewall, DNS, etc) should be put to test. The steps for this are below, in a tentative order that seems to make most sense.



### TERMS:

- **Legacy:** Refers to the source aws account that we are migrating from.
- **CSS:** Refers to the "Common Security Services" aws account that we are migrating to.

### DIFFERENCES:

1. **Addressing**
   Domain names will change for application and the database. Example: `stg.kualitest.research.bu.edu` vs. `kuali-research-stg.bu.edu`.
2. **Database**
   - Old: EC2 host, oracle enterprise edition 12
   - New: RDS host, oracle standard edition 19
3. **Tighter health checks**
   - Old: Checks only for tomcat being available
   - New: Checks that kuali research app under tomcat is reachable, and that the database can be reached by it.
4. **[Elastic container services](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html)**
   Kuali-research will now run in a fault tolerant, auto-scaling cluster that will swap out application hosts based on load and health status.
5. **[Web Application Firewall (WAF)](https://aws.amazon.com/waf/)**
   A web application firewall will now be in use that will block requests deemed to be unsafe.

### RUNBOOK TASKS:

1. **Create RDS Database**
   Create a data duplicate of the legacy oracle database for kc in the CSS account as an RDS instance. This will drift away from duplicate status as time goes on, but that's ok for testing (this step will be repeated on "release night")
   - Warren Hennemuth: [database runbook (all steps)](database.md)
2. **TESTING (No app)**:
   1. **ETL: SAP & Mongo nightly update Testing**
      This will include a quick repeat of the testing done here: [ENHC0025972](https://bu.service-now.com/nav_to.do?uri=%2Frm_enhancement.do%3Fsys_id%3Dfc416e641becf410f2b8f5f61a4bcb82%26sysparm_stack%3Drm_enhancement_list.do%3Fsysparm_query%3Dactive%3Dtrue).
      - Rohini Bhuvarahamurthy
   2. **SAP BW Testing**
      This will involve a re-confirmation of the final connectivity success result reached at the end of prior testing: [SAP Testing](sap/sap.htm)
      Also a the full end-to-end test should be considered.
      - Rohit Bhargava
      - *[Possible Others]*
         - Alex Chen
         - Pratik Shah
         - Gee Lee
3. **CREATE APPLICATION STACK:**
   - Warren Hennemuth: [application runbook](application.md)
4. **TESTING (With app):**
   1. **Application regression testing and UAT** 
      Run any and all regression test suites created to date by QA.
      Any differences/failures in operation would stem from the differences listed above. So, we would want, for example, to go 
      - Christine Gagnon?
      - John Nickerson
      - Hitesh Tara
      - Warren Hennemuth
      - Dean Haywood
      - Vanessa Craige
   2. **Snap Logic Testing**
      TODO: Who and what?
5. **TESTING (Release):**
   1. **Mock release**
      - Warren Hennemuth
         - Shut down the ec2 instances for kuali-research in the legacy account.
         - Replace the 2 shutdown ec2 instance entries in the load balancer with a single micro instance that serves up a "kuali-research has moved" html page.
   2. **Mock release abort testing**
      Undo the mock release and bring back the original app.
      - Warren Hennemuth

