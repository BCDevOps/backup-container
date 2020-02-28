
## An example of the backup container in action
```
Starting backup process ...
Reading backup config from backup.conf ...
Making backup directory /backups/daily/2020-02-28/ ...

Settings:
- Run mode: scheduled

- Backup strategy: rolling
- Current backup type: daily
- Backups to retain:
  - Daily: 6
  - Weekly: 4
  - Monthly: 1
- Current backup folder: /backups/daily/2020-02-28/
- Time Zone: PST -0800

- Schedule:
  - 0 1 * * * default ./backup.sh -s
  - 0 4 * * * default ./backup.sh -s -v all

- Container Type: mongo
- Databases (filtered by container type):
  - mongo=identity-kit-db-bc/identity_kit_db

- FTP server: not configured
- Webhook Endpoint: https://chat.pathfinder.gov.bc.ca/hooks/***
- Environment Friendly Name: Verifiable Organizations Network (mongo-test)
- Environment Name (Id): devex-von-test

Backing up 'identity-kit-db-bc/identity_kit_db' to '/backups/daily/2020-02-28/identity-kit-db-bc-identity_kit_db_2020-02-28_08-07-10.sql.gz.in_progress' ...
Successfully backed up mongo=identity-kit-db-bc/identity_kit_db.
Backup written to /backups/daily/2020-02-28/identity-kit-db-bc-identity_kit_db_2020-02-28_08-07-10.sql.gz.
Database Size: 1073741824
Backup Size: 4.0K

Elapsed time: 0h:0m:0s - Status Code: 0

================================================================================================================================
Current Backups:

Database                                  Current Size
mongo=identity-kit-db-bc/identity_kit_db  1073741824

Filesystem                                                                                                   Size  Used Avail Use% Mounted on
192.168.111.90:/trident_qtree_pool_file_standard_WKDMGDWTSQ/file_standard_devex_von_test_backup_mongo_54218  1.0G     0  1.0G   0% /backups
--------------------------------------------------------------------------------------------------------------------------------
4.0K    2020-02-27 13:26        /backups/daily/2020-02-27/identity-kit-db-bc-identity_kit_db_2020-02-27_13-26-21.sql.gz
4.0K    2020-02-27 13:27        /backups/daily/2020-02-27/identity-kit-db-bc-identity_kit_db_2020-02-27_13-27-10.sql.gz
12K     2020-02-27 13:27        /backups/daily/2020-02-27
4.0K    2020-02-28 06:44        /backups/daily/2020-02-28/identity-kit-db-bc-identity_kit_db_2020-02-28_06-44-19.sql.gz
4.0K    2020-02-28 07:12        /backups/daily/2020-02-28/identity-kit-db-bc-identity_kit_db_2020-02-28_07-12-29.sql.gz
4.0K    2020-02-28 08:07        /backups/daily/2020-02-28/identity-kit-db-bc-identity_kit_db_2020-02-28_08-07-10.sql.gz
16K     2020-02-28 08:07        /backups/daily/2020-02-28
32K     2020-02-28 08:07        /backups/daily
36K     2020-02-28 08:07        /backups/
================================================================================================================================

Scheduled backup run complete.
```