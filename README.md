
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

# Backup Container

This is a simple containerized backup solution for backing up postgres databases to a secondary location.  _Code and documentation was oringinally pulled from the [HETS Project](https://github.com/bcgov/hets)_

Postgres Backups in OpenShift
----------------
This project helps you create an OpenShift deployment called "backup" in your projects that runs backups on a Postgres database. The following are the instructions for running the backups and a restore.

Deployment / Configuration
----------------
The OpenShift Deployment Template for this application will automatically deploy the Backup app as described below.

The following environment variables are used by the Backup app.

**NOTE**: THESE ENVIRONMENT VARIABLES MUST MATCH THE VARIABLES USED BY THE postgresql DEPLOYMENT DESCRIPTOR.

| Name | Purpose |
| ---- | ------- |
| DATABASE_SERVICE_NAME | hostname for the database to backup |
| POSTGRESQL_USER | database user for the backup |
| POSTGRESQL_PASSWORD | database password for the backup |
| POSTGRESQL_DATABASE | database to backup | 
| BACKUP_DIR | directory to store the backups |

The BACKUP_DIR must be set to a location that has persistent storage.

Backup
------
The purpose of the backup app is to do automatic backups.  Deploy the Backup app to do daily backups.  Viewing the Logs for the Backup App will show a record of backups that have been completed.

The Backup app performs the following sequence of operations:

1. Create a directory that will be used to store the backup.
2. Use the `pg_dump` and `gzip` commands to make a backup.
3. Cull backups more than $NUM_BACKUPS (default 31 - configured in deployment script)
4. Sleep for a day and repeat

Note that we are just using a simple "sleep" to run the backup periodically. More elegent solutions were looked at briefly, but there was not a lot of time or benefit, so OpenShift Scheduled Jobs, cron and so on are not used. With some more effort they likely could be made to work.

A separate pod is used vs. having the backups run from the Postgres Pod for fault tolerent purposes - to keep the backups separate from the database storage.  We don't want to, for example, lose the storage of the database, or have the database and backups storage fill up, and lose both the database and the backups.

Immediate Backup:
-----------------
To execute a backup right now, check the logs of the Backup pod to make sure a backup isn't run right now (pretty unlikely...), and then deploy the "backup" using OpenShift "deploy" capabilities.

Restore
-------
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

To report bugs/issues/feature requests, please file an [issue](../../issues).

## How to Contribute

If you would like to contribute, please see our [CONTRIBUTING](./CONTRIBUTING.md) guidelines.

Please note that this project is released with a [Contributor Code of Conduct](./CODE_OF_CONDUCT.md). 
By participating in this project you agree to abide by its terms.

## License

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
