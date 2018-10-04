
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

# Backup Container
This is a simple containerized backup solution for backing up one or more postgres databases to a secondary location.  _Code and documentation was oringinally pulled from the [HETS Project](https://github.com/bcgov/hets)_

## Postgres Backups in OpenShift
----
This project provides you with a starting point for integrating backups into your OpenShift projects.  The scripts and templates provided in the [openshift](./openshift) directory are compatible with the [openshift-developer-tools](https://github.com/BCDevOps/openshift-developer-tools) scripts.  They help you create an OpenShift deployment called `backup` in your projects that runs backups on a Postgres database(s) within the project environment.  You only need to integrate the scripts and templates into your project(s), the builds can be done with this repository as the source.

Following are the instructions for running the backups and a restore.

## Deployment / Configuration
----
Together, the scripts and templates provided in the [openshift](./openshift) directory will automatically deploy the `backup` app as described below.  The [backup-deploy.overrides.sh](./openshift/backup-deploy.overrides.sh) script generates the deployment configuration necessary for the [backup.conf](config/backup.conf) file to be mounted as a ConfigMap by the `backup` container.

The following environment variables are defaults used by the `backup` app.

**NOTE**: These environment variables MUST MATCH those used by the postgresql container(s) you are planning to backup.

| Name | Default (if not set) | Purpose |
| ---- | ------- | ------- |
| BACKUP_STRATEGY | daily | To control the backup strategy used for backups.  This is explained more below. |
| BACKUP_DIR | /backups/ | The directory under which backups will be stored.  The deployment configuration mounts the persistent volume claim to this location when first deployed. |
| NUM_BACKUPS | 31 | For backward compatibility this value is used with the daily backup strategy to set the number of backups to retain before pruning. |
| DAILY_BACKUPS | 6 | When using the rolling backup strategy this value is used to determine the number of daily (Mon-Sat) backups to retain before pruning. |
| WEEKLY_BACKUPS | 4 | When using the rolling backup strategy this value is used to determine the number of weekly (Sun) backups to retain before pruning. |
| MONTHLY_BACKUPS | 1 | When using the rolling backup strategy this value is used to determine the number of monthly (last day of the month) backups to retain before pruning. |
| BACKUP_PERIOD | 1d | The schedule on which to run the backups.  The value is used by a sleep command and can be defined in d, h, m, or s. |
| DATABASE_SERVICE_NAME | postgresql | The name of the service/host for the *default* database target. |
| POSTGRESQL_DATABASE | my_postgres_db | The name of the *default* database target; the name of the database you want to backup. |
| POSTGRESQL_USER | *wired to a secret* | The username for the database(s) hosted by the `postgresql` Postgres server. The deployment configuration makes the assumption you have your database credentials stored in secrets (which you should), and the key for the username is `database-user`.  The name of the secret must be provided as the `DATABASE_DEPLOYMENT_NAME` parameter to the deployment configuration template. |
| POSTGRESQL_PASSWORD | *wired to a secret* | The password for the database(s) hosted by the `postgresql` Postgres server. The deployment configuration makes the assumption you have your database credentials stored in secrets (which you should), and the key for the username is `database-password`.  The name of the secret must be provided as the `DATABASE_DEPLOYMENT_NAME` parameter to the deployment configuration template. |

Using this default configuration you can easily back up a single postgres database, however you can extend the configuration and use the `backup.conf` file to list a number of databases for backup.

When using the `backup.conf` file the following environment variables are ignored, since you list all of your `host`/`database` pairs in the file; `DATABASE_SERVICE_NAME`, `POSTGRESQL_DATABASE`.  To provide the credentials needed for the listed databases you extend the deployment configuration to include `hostname_USER` and `hostname_PASSWORD` credential pairs which are wired to the appropriate secrets (where hostname matches the hostname/servicename, in all caps and underscores, of the database).  For example, if you are backing up a database named `wallet-db/my_wallet`, you would have to extend the deployment configuration to include a `WALLET_DB_USER` and `WALLET_DB_PASSWORD` credential pair, wired to the appropriate secrets, to access the database(s) on the `wallet-db` server.  You may notice the default configuration is already wired for the host/service name `postgresql`, so you're already covered if all your databases are on a server of that name.

## Multiple Databases

When backing up multiple databases, the retention settings apply to each database individually.  For instance if you use the `daily` strategy and set the retention number(s) to 5, you will retain 5 copies of each database.  So plan your backup storage accordingly.

An example of the backup container in action can be found here; [example log output](./ExampleLog.md)

## Backup Strategies
---

The `backup` app supports two backup strategies, each are explained below.  Regardless of the strategy backups are identified using a core name derived from the `host/database` specification and a timestamp.  All backups are compressed using gzip.

### Daily

The daily backup strategy is very simple.  Backups are created in dated folders under the top level `/backups/` folder.  When the maximum number of backups (`NUM_BACKUPS`) is exceeded, the oldest ones are pruned from disk.

For example (faked):
```
================================================================================================================================
Current Backups:
--------------------------------------------------------------------------------------------------------------------------------
1.0K    2018-10-03 22:16        ./backups/2018-10-03/postgresql-TheOrgBook_Database_2018-10-03_22-16-11.sql.gz
1.0K    2018-10-03 22:16        ./backups/2018-10-03/postgresql-TheOrgBook_Database_2018-10-03_22-16-28.sql.gz
1.0K    2018-10-03 22:16        ./backups/2018-10-03/postgresql-TheOrgBook_Database_2018-10-03_22-16-46.sql.gz
1.0K    2018-10-03 22:16        ./backups/2018-10-03/wallet-db-tob_holder_2018-10-03_22-16-13.sql.gz
1.0K    2018-10-03 22:16        ./backups/2018-10-03/wallet-db-tob_holder_2018-10-03_22-16-31.sql.gz
1.0K    2018-10-03 22:16        ./backups/2018-10-03/wallet-db-tob_holder_2018-10-03_22-16-48.sql.gz
1.0K    2018-10-03 22:16        ./backups/2018-10-03/wallet-db-tob_verifier_2018-10-03_22-16-08.sql.gz
1.0K    2018-10-03 22:16        ./backups/2018-10-03/wallet-db-tob_verifier_2018-10-03_22-16-25.sql.gz
1.0K    2018-10-03 22:16        ./backups/2018-10-03/wallet-db-tob_verifier_2018-10-03_22-16-43.sql.gz
13K     2018-10-03 22:16        ./backups/2018-10-03
...
61K     2018-10-04 10:43        ./backups/
================================================================================================================================
```

### Rolling

The rolling backup strategy provides a bit more flexibility.  It allows you to keep a number of recent `daily` backups, a number of `weekly` backups, and a number of `monthly` backups.

- Daily backups are any backups done Monday through Saturday.
- Weekly backups are any backups done at the end of the week, which we're calling Sunday.
- Monthly backups are any backups done on the last day of a month.

There are retention settings you can set for each.  The defaults provide you with a week's worth of `daily` backups, a month's worth of `weekly` backups, and a single backup for the previous month.

Although the example does not show any `weekly` or `monthly` backups, you can see from the example that the folders are further broken down into the backup type.

For example (faked):
```
================================================================================================================================
Current Backups:
--------------------------------------------------------------------------------------------------------------------------------
0       2018-10-03 22:16        ./backups/daily/2018-10-03
1.0K    2018-10-04 09:29        ./backups/daily/2018-10-04/postgresql-TheOrgBook_Database_2018-10-04_09-29-52.sql.gz
1.0K    2018-10-04 10:37        ./backups/daily/2018-10-04/postgresql-TheOrgBook_Database_2018-10-04_10-37-15.sql.gz
1.0K    2018-10-04 09:29        ./backups/daily/2018-10-04/wallet-db-tob_holder_2018-10-04_09-29-55.sql.gz
1.0K    2018-10-04 10:37        ./backups/daily/2018-10-04/wallet-db-tob_holder_2018-10-04_10-37-18.sql.gz
1.0K    2018-10-04 09:29        ./backups/daily/2018-10-04/wallet-db-tob_verifier_2018-10-04_09-29-49.sql.gz
1.0K    2018-10-04 10:37        ./backups/daily/2018-10-04/wallet-db-tob_verifier_2018-10-04_10-37-12.sql.gz
22K     2018-10-04 10:43        ./backups/daily/2018-10-04
22K     2018-10-04 10:43        ./backups/daily
4.0K    2018-10-03 22:16        ./backups/monthly/2018-10-03
4.0K    2018-10-03 22:16        ./backups/monthly
4.0K    2018-10-03 22:16        ./backups/weekly/2018-10-03
4.0K    2018-10-03 22:16        ./backups/weekly
61K     2018-10-04 10:43        ./backups/
================================================================================================================================
```

## Using the Backup Script
---

The [backup script](./docker/backup.sh) has a few utility features built into it.  Running `backup.sh -h` will provide a full list.

Features include the ability to list the existing backups, `backup.sh -l`, on the system from the command line, and list the current configuration , `backup.sh -c`, without running the backup.

## Backup
---
The purpose of the backup app is to do automatic backups.  Deploy the Backup app to do daily backups.  Viewing the Logs for the Backup App will show a record of backups that have been completed.

The Backup app performs the following sequence of operations:

1. Create a directory that will be used to store the backup.
2. Use the `pg_dump` and `gzip` commands to make a backup.
3. Cull backups more than $NUM_BACKUPS (default 31 - configured in deployment script)
4. Sleep for a day and repeat

Note that we are just using a simple "sleep" to run the backup periodically. More elegent solutions were looked at briefly, but there was not a lot of time or benefit, so OpenShift Scheduled Jobs, cron and so on are not used. With some more effort they likely could be made to work.

A separate pod is used vs. having the backups run from the Postgres Pod for fault tolerent purposes - to keep the backups separate from the database storage.  We don't want to, for example, lose the storage of the database, or have the database and backups storage fill up, and lose both the database and the backups.

### Immediate Backup:

To execute a backup right now, check the logs of the Backup pod to make sure a backup isn't run right now (pretty unlikely...), and then deploy the "backup" using OpenShift "deploy" capabilities.

### Restore

These steps perform a restore of a backup.

1. Log into the OpenShift Console and log into OpenShift on the command shell window.
   1. The instructions here use a mix of the console and command line, but all could be done from a command shell using "oc" commands. We have not written a script for this as if a backup is needed, something has gone seriously wrong, and compensating steps may be needed for which the script would not account.
2. Scale to 0 all Apps that use the database connection.
   1. This is necessary as the Apps will need to restart to pull data from the restored backup.
   3. It is recommended that you also scale down to 0 your client application so that users know the application is unavailable while the database restore is underway.
       1. A nice addition to this would be a user-friendly "This application is offline" message - not yet implemented.
3. Restart the **postgres** pod as a quick way of closing any other database connections from users using port forward or that have rsh'd to directly connect to the database.
4. Open an rsh into the Postgres pod.
   1. Open a command prompt connection to OpenShift using `oc login` with parameters appropriate for your OpenShift host.
   2. Change to the OpenShift project containing the Backup App `oc project <Project Name>`
   3. List pods using `oc get pods`
   4. Open a remote shell connection to the **postgresql** pod. `oc rsh <Postgresql Pod Name>`
5. In the rsh run `psql` 
6. Get the name of the database and the Application user - you need to know these for later steps.
   1. Run the shell command: `echo Database Name: $POSTGRESQL_DATABASE`
   2. Run the shell command: `echo App User: $POSTGRESQL_USER`
7. Execute `drop <database name>;` to drop the database (database name from above).
8. Execute `create <database name>;` to create a new instance of the database with the same name as the old one.
9. Execute `grant all on database hets to "<name of $POSTGRESQL_USER>";`
    1. If there are other users needing access to the database, such as the DBA group:
        2. Get a list of the users by running the command `\du`
        2. For each user that is not "postgres" and $POSTGRESQL_USER, execute the command `GRANT SELECT ON ALL TABLES IN SCHEMA public TO "<name of user>";`
    2. If users have been set up with other grants, set them up as well.
10. Close psql with `\q`
11. Exit rsh with `exit` back to your local command line
12. Execute `oc rsh <Backup Pod Name>` to remote shell into the backup app pod
13. Change to the bash shell by entering `bash`
14. Change to the directory containing the backup you wish to restore and find the name of the file.
15. Execute the following bash commands:
    1. `PGPASSWORD=$POSTGRESQL_PASSWORD`
    2. `export PGPASSWORD`
    3. `gunzip -c <filename> | psql -h "$DATABASE_SERVICE_NAME" -U "$POSTGRESQL_USER" "$POSTGRESQL_DATABASE" "$POSTGRESQL_DATABASE"`
       1. Ignore the "no privileges revoked" warnings at the end of the process.
16. Verify that the database restore worked
    1. `psql -h "$DATABASE_SERVICE_NAME" -U "$POSTGRESQL_USER" "$POSTGRESQL_DATABASE"`
    2. `\d`
    3. Verify that application tables are listed. Query a table - e.g the USER table:
    4. `SELECT * FROM "SBI_USER";` - you can look at other tables if you want.
    5. Verify data is shown.
    6. `\q`
17. Exit remote shells back to your local commmand line
18. From the Openshift Console restart the app:
    1. Scale up any pods you scaled down and wait for them to finish starting up.  View the logs to verify there were no startup issues.
19.  Verify full application functionality.

Done!

## Getting Help or Reporting an Issue
---
To report bugs/issues/feature requests, please file an [issue](../../issues).

## How to Contribute
---
If you would like to contribute, please see our [CONTRIBUTING](./CONTRIBUTING.md) guidelines.

Please note that this project is released with a [Contributor Code of Conduct](./CODE_OF_CONDUCT.md). 
By participating in this project you agree to abide by its terms.

## License
---
    Copyright 2018 Province of British Columbia

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
