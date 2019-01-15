
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

# Backup Container
This is a simple containerized backup solution for backing up one or more postgres databases to a secondary location.  _Code and documentation was originally pulled from the [HETS Project](https://github.com/bcgov/hets)_

## Postgres Backups in OpenShift
----
This project provides you with a starting point for integrating backups into your OpenShift projects.  The scripts and templates provided in the [openshift](./openshift) directory are compatible with the [openshift-developer-tools](https://github.com/BCDevOps/openshift-developer-tools) scripts.  They help you create an OpenShift deployment or cronjob called `backup` in your projects that runs backups on a Postgres database(s) within the project environment.  You only need to integrate the scripts and templates into your project(s), the builds can be done with this repository as the source.

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
| FTP_URL |  | The FTP server URL. If not specified, the FTP backup feature is disabled. The default value in the deployment configuration is an empty value - not specified. |
| FTP_USER | *wired to a secret* | The username for the FTP server. The deployment configuration creates a secret with the name specified in the FTP_SECRET_KEY parameter (default: `ftp-secret`). The key for the username is `ftp-user` and the value is an empty value by default. |
| FTP_PASSWORD | *wired to a secret* | The password for the FTP server. The deployment configuration creates a secret with the name specified in the FTP_SECRET_KEY parameter (default: `ftp-secret`). The key for the password is `ftp-password` and the value is an empty value by default. |

Using this default configuration you can easily back up a single postgres database, however you can extend the configuration and use the `backup.conf` file to list a number of databases for backup.

When using the `backup.conf` file the following environment variables are ignored, since you list all of your `host`/`database` pairs in the file; `DATABASE_SERVICE_NAME`, `POSTGRESQL_DATABASE`.  To provide the credentials needed for the listed databases you extend the deployment configuration to include `hostname_USER` and `hostname_PASSWORD` credential pairs which are wired to the appropriate secrets (where hostname matches the hostname/servicename, in all caps and underscores, of the database).  For example, if you are backing up a database named `wallet-db/my_wallet`, you would have to extend the deployment configuration to include a `WALLET_DB_USER` and `WALLET_DB_PASSWORD` credential pair, wired to the appropriate secrets, to access the database(s) on the `wallet-db` server.  You may notice the default configuration is already wired for the host/service name `postgresql`, so you're already covered if all your databases are on a server of that name.

### Cronjob Deployment / Configuration / Constraints

The cronjob object can be deployed in the same manner as the application, and will also have a dependency on the image built by the build config.  The main constraint for the cronjob objects is that they will require a configmap in place of environment variables and does not support the `backup.conf` for multiple database backups in the same job.  In order to backup multiple databases, create multiple cronjob objects with their associated configmaps and secrets.

The following variables are supported in the first iteration of the backup cronjob:

| Name | Default (if not set) | Purpose |
| ---- | ------- | ------- |
| BACKUP_STRATEGY | daily | To control the backup strategy used for backups.  This is explained more below. |
| BACKUP_DIR | /backups/ | The directory under which backups will be stored.  The deployment configuration mounts the persistent volume claim to this location when first deployed. |
| NUM_BACKUPS | 31 | For backward compatibility this value is used with the daily backup strategy to set the number of backups to retain before pruning. |
| DAILY_BACKUPS | 6 | When using the rolling backup strategy this value is used to determine the number of daily (Mon-Sat) backups to retain before pruning. |
| WEEKLY_BACKUPS | 4 | When using the rolling backup strategy this value is used to determine the number of weekly (Sun) backups to retain before pruning. |
| MONTHLY_BACKUPS | 1 | When using the rolling backup strategy this value is used to determine the number of monthly (last day of the month) backups to retain before pruning. |
| DATABASE_SERVICE_NAME | postgresql | The name of the service/host for the *default* database target. |
| POSTGRESQL_DATABASE | my_postgres_db | The name of the *default* database target; the name of the database you want to backup. |
| POSTGRESQL_USER | *wired to a secret* | The username for the database(s) hosted by the `postgresql` Postgres server. The deployment configuration makes the assumption you have your database credentials stored in secrets (which you should), and the key for the username is `database-user`.  The name of the secret must be provided as the `DATABASE_DEPLOYMENT_NAME` parameter to the deployment configuration template. |
| POSTGRESQL_PASSWORD | *wired to a secret* | The password for the database(s) hosted by the `postgresql` Postgres server. The deployment configuration makes the assumption you have your database credentials stored in secrets (which you should), and the key for the username is `database-password`.  The name of the secret must be provided as the `DATABASE_DEPLOYMENT_NAME` parameter to the deployment configuration template. |

The following variables are NOT supported:

| BACKUP_PERIOD | 1d | The schedule on which to run the backups.  The value is replaced by the cron schedule variable (SCHEDULE)

The scheduled job does not yet support the FTP environment variables.

| FTP_URL
| FTP_USER
| FTP_PASSWORD

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

The [backup script](./docker/backup.sh) has a few utility features built into it.  For a full list of features and documentation run `backup.sh -h`.

Features include:

- The ability to list the existing backups, `backup.sh -l`
- Listing the current configuration, `backup.sh -c`
- Running a single backup cycle, `backup.sh -1`
- Restoring a database from backup, `backup.sh -r <databaseSpec/> [-f <backupFileFilter>]`
  - Restore mode will allow you to restore a database to a different location (host, and/or database name) provided it can contact the host and you can provide the appropriate credentials.

## Using the FTP backup

- The FTP backup feature is enabled by specifying the FTP server URL `FTP_URL`.
- The FTP server must support FTPS.
- Path can be added to the URL. For example, the URL can be `ftp://ftp.gov.bc.ca/schoolbus-db-backup/`. Note that when adding path, the URL must be ended with `/` as the example.
- The username and password must be populated in the secret key. Refer to the deployment configuration section.
- There is a known issue for FTPS with Windows 2012 FTP. http://redoubtsolutions.com/fix-the-supplied-message-is-incomplete-error-when-you-use-an-ftps-client-to-upload-a-file-in-windows/

## Backup
---
The purpose of the backup app is to do automatic backups.  Deploy the Backup app to do daily backups.  Viewing the Logs for the Backup App will show a record of backups that have been completed.

The Backup app performs the following sequence of operations:

1. Create a directory that will be used to store the backup.
2. Use the `pg_dump` and `gzip` commands to make a backup.
3. Cull backups more than $NUM_BACKUPS (default 31 - configured in deployment script)
4. Sleep for a day and repeat

Note that with the pod deployment, we are just using a simple "sleep" to run the backup periodically.  With the OpenShift Scheduled Job deployment, use the backup-cronjob.yaml template and set the schedule via the cronjob object SCHEDULE template parameter.

A separate pod is used vs. having the backups run from the Postgres Pod for fault tolerant purposes - to keep the backups separate from the database storage.  We don't want to, for example, lose the storage of the database, or have the database and backups storage fill up, and lose both the database and the backups.

### Immediate Backup:

#### Execute a single backup cycle with the pod deployment

- Check the logs of the Backup pod to make sure a backup isn't run right now (pretty unlikely...)
- Open a terminal window to the pod
- Run `backup.sh -1`
  - This will run a single backup cycle and exit.

#### Execute an on demand backup using the scheduled job

- Run the following: `oc create job ${SOMEJOBNAME} --from=cronjob/${BACKUP_CRONJOB_NAME}`
  - example: `oc create job my-backup-1 --from=cronjob/backup-postgresql`
  - this will run a single backup job and exit.
  - note: the jobs created in this manner are NOT cleaned up by the scheduler like the automated jobs are.

### Restore

The `backup.sh` script's restore mode makes it very simple to restore the most recent backup of a particular database.  It's as simple as running a the following command, for example (run `backup.sh -h` for full details on additional options);

    backup.sh -r postgresql/TheOrgBook_Database

Following are more detailed steps to perform a restore of a backup.

1. Log into the OpenShift Console and log into OpenShift on the command shell window.
   1. The instructions here use a mix of the console and command line, but all could be done from a command shell using "oc" commands.
1. Scale to 0 all Apps that use the database connection.
   1. This is necessary as the Apps will need to restart to pull data from the restored backup.
   1. It is recommended that you also scale down to 0 your client application so that users know the application is unavailable while the database restore is underway.
       1. A nice addition to this would be a user-friendly "This application is offline" message - not yet implemented.
1. Restart the database pod as a quick way of closing any other database connections from users using port forward or that have rsh'd to directly connect to the database.
1. Open an rsh into the backup pod:
   1. Open a command prompt connection to OpenShift using `oc login` with parameters appropriate for your OpenShift host.
   1. Change to the OpenShift project containing the Backup App `oc project <Project Name>`
   1. List pods using `oc get pods`
   1. Open a remote shell connection to the **backup** pod. `oc rsh <Backup Pod Name>`
1. In the rsh run the backup script in restore mode, `./backup.sh -r <DatabaseSpec/>`, to restore the desired backup file.  For full information on how to use restore mode, refer to the script documentation, `./backup.sh -h`.  Have the Admin password for the database handy, the script will ask for it during the restore process.
    1. The restore script will automatically grant the database user access to the restored database.  If there are other users needing access to the database, such as the DBA group, you will need to additionally run the following commands on the database pod itself using `psql`:
        1. Get a list of the users by running the command `\du`
        1. For each user that is not "postgres" and $POSTGRESQL_USER, execute the command `GRANT SELECT ON ALL TABLES IN SCHEMA public TO "<name of user>";`
    1. If users have been set up with other grants, set them up as well.
1. Verify that the database restore worked
    1. On the database pod, query a table - e.g the USER table: `SELECT * FROM "SBI_USER";` - you can look at other tables if you want.
    1. Verify the expected data is shown.
1. Exit remote shells back to your local commmand line
1. From the Openshift Console restart the app:
    1. Scale up any pods you scaled down and wait for them to finish starting up.  View the logs to verify there were no startup issues.
1.  Verify full application functionality.

Done!

## Getting Help or Reporting an Issue
---
To report bugs/issues/feature requests, please file an [issue](../../issues).

## How to Contribute
---
If you would like to contribute, please see our [CONTRIBUTING](./CONTRIBUTING.md) guidelines.

Please note that this project is released with a [Contributor Code of Conduct](./CODE_OF_CONDUCT.md). 
By participating in this project you agree to abide by its terms.