## RELEASE RUNBOOK

#### <img align="left" src="checklist-release.png">Kuali Research "release night" migration to common security services aws account.

This is the sequencing of work and assignments that will go into transitioning the kuali research application stack to the common security services (CSS) account and retiring the current aws cloud account where it is currently running.

This runbook will be used one or more times for the staging environment, each test run being tweaked until it can go end to end without issue. Then the last successful staging run will be repeated once for the production environment.



### TERMS:

- **Legacy:** Refers to the source aws account that we are migrating from.
- **CSS:** Refers to the "Common Security Services" aws account that we are migrating to.

### PRE-RELEASE STATE:

- **Testing status:**
  All testing completed as covered in the [pre-release runbook](pre-release.md)
- **CSS Database:**
  Up and running, but out of sync with the legacy database. Not a data duplicate.
- **CSS Application:**
  Up and running. Kuali reachable in the browser at it's new url.
- **ETL, SAP, SAPBW, SNAPLOGIC:**
  Each have, in the past, temporarily cutover to test the new app/database as detailed in the [pre-release runbook](pre-release.md), however none are cutover at this point.
- **Legacy application/database:**
  Up and running at the original url.

### RUNBOOK TASKS:

1. **Database Quarantine**
   Quarantine the legacy oracle database
1. **Database Re-migration**
   Retake and share RDS snapshot to reintroduce data duplicate conditions between accounts.
   Essentially we are swapping out the CSS RDS with a data-duplicate of the legacy database.
   - Warren: [database runbook (steps 6-12)](database.md)
3. **Verify connectivity**
   - Warren:  Perform a browser smoke test.
   - Rohini: Perform database connectivity test from corresponding informatica server.
4. Coordinate with SAPBW participants to test each of the routine direct-to-database jobs against the RDS database. Testing for: 
   - Database connectivity issues
   - Authorization issues against required schemas, tables and views.
   - Trial runs against both RDS and original databases to ensure apples to apples results are identical.
5. Coordinate with Carmines team to test each of the routine ETL jobs run against the kuali database/application. Testing for:
   - All the same things as tested with SAPBW participants can be repeated with ETL participants.
   - Stand up an application stack tied to the RDS clone: Some ETL jobs are run against the application and not the database directly. One such process access the cor-main service. In a new stack this service starts with a blank user base unless otherwise configured to point at an existing mongo atlas db (not advised, as these are limited and already tied to existing application stacks). The initial data load for core can be tested, followed by more routine jobs.
6. Coordinate with Snaplogic participants to test ongoing contact with the kuali web api at its new URL(s). Testing for:
   - All the same things as tested with SAPBW participants can be repeated with Snaplogic participants.
7. Work with Christine Gagnon and John Nickerson to test the new staging application stack itself. Testing for:
   - Ongoing migration is producing valid results. Both target RDS and source databases should have identical row counts. I have written a script that compares a two and produces output detailing any discrepancies.
   - Beyond row count comparisons, spot checks in selected locations for the data itself can be made, focusing on rows that are known to be changing due to application activity.
   - Run full battery of regression tests for Kuali.
   - The new Kuali environment is deployed to an ECS cluster. This means that a new set of features are added that go on behind the scenes that ensure better fault tolerance and auto-scaling. Discussion should occur over which of these features, if any, are candidates for testing. For example, while auto-scaling is a crucial feature for true micro-services and lightweight distributed applications, Kuali will probably not be able to effectively use this feature. I can go into more detail at a later time.
8. User acceptance testing?
9. Have networking install a URL record for issuing a 301 status and related endpoint as a new DNS entry for the kuali staging environment so that any incoming requests for the old URL are redirected to the new URL. This should be created, but not enabled (will "pull the trigger" on it the night of cutover).
10. Once all testing is successful, the cutover to the new account can begin.
   1. This requires the source database to be isolated, accepting no incoming traffic. A time is picked when no jobs or automated processes are scheduled to access the source kuali database or application. As a guarantee of database "quarantine" we can additionally:
   2. Delete any staging application stacks and related RDS clones.
   3. Notify the user base that the staging environment for kuali will be temporarily unavailable.
   4. Take the original kuali application ec2 instances off their load balancer to discontinue their access to the source database.
   5. Optionally, at this point we can help guarantee database "quarantine" by additionally:
      - Adding a restrictive ingress rule to the database security group.
         or...
      - Stopping the database servers themselves.
   6. Run prepared script to update target RDS database sequences (repeat steps for this as described earlier).
   7. Run prepared script to reenable all triggers and constraints (repeat steps for this as described earlier).
   8. Create the new staging application stack, pointing it at the primary RDS database this time (not a clone). NOTE: This time the cor-main service should be pointing at the mongo atlas database.
   9. Run initial smoke tests against the application as would be done after any new release.
   10. Enable the DNS redirect for the staging environment.
   11. Notify users that the staging environment is available at its new URL.
11. At this point, a vetting period begins for the staging environment. This trial period will have a duration that we all jointly decide upon and are comfortable with. *(During this period, the RDS database will be set up for production with ongoing migration enabled.)*



