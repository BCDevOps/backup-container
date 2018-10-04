
## An example of the backup container in action
```
Starting backup process ...
Reading backup config from backup.conf ...
Making backup directory /backups/daily/2018-10-04/ ...

Settings:
- Backup strategy: rolling
- Backup type: daily
- Number of each backup to retain: 6
- Backup folder: /backups/daily/2018-10-04/
- Databases:
  - wallet-db:5432/tob_verifier
  - postgresql:5432/TheOrgBook_Database
  - wallet-db:5432/tob_holder

Backing up wallet-db:5432/tob_verifier ...
Elapsed time: 0h:0m:1s
Backup written to /backups/daily/2018-10-04/wallet-db-tob_verifier_2018-10-04_22-49-39.sql.gz ...

Backing up postgresql:5432/TheOrgBook_Database ...
Elapsed time: 0h:2m:48s
Backup written to /backups/daily/2018-10-04/postgresql-TheOrgBook_Database_2018-10-04_22-49-41.sql.gz ...

Backing up wallet-db:5432/tob_holder ...
Elapsed time: 0h:24m:34s
Backup written to /backups/daily/2018-10-04/wallet-db-tob_holder_2018-10-04_22-52-29.sql.gz ...

================================================================================================================================
Current Backups:
--------------------------------------------------------------------------------------------------------------------------------
4.0K	2018-10-04 17:10	/backups/.trashcan/internal_op
8.0K	2018-10-04 17:10	/backups/.trashcan
3.5K	2018-10-04 17:17	/backups/daily/2018-10-04/wallet-db-tob_verifier_2018-10-04_17-17-02.sql.gz
687M	2018-10-04 17:20	/backups/daily/2018-10-04/postgresql-TheOrgBook_Database_2018-10-04_17-17-03.sql.gz
9.1G	2018-10-04 17:44	/backups/daily/2018-10-04/wallet-db-tob_holder_2018-10-04_17-20-06.sql.gz
3.5K	2018-10-04 17:48	/backups/daily/2018-10-04/wallet-db-tob_verifier_2018-10-04_17-48-42.sql.gz
687M	2018-10-04 17:51	/backups/daily/2018-10-04/postgresql-TheOrgBook_Database_2018-10-04_17-48-44.sql.gz
9.1G	2018-10-04 18:16	/backups/daily/2018-10-04/wallet-db-tob_holder_2018-10-04_17-51-36.sql.gz
3.5K	2018-10-04 22:49	/backups/daily/2018-10-04/wallet-db-tob_verifier_2018-10-04_22-49-39.sql.gz
687M	2018-10-04 22:52	/backups/daily/2018-10-04/postgresql-TheOrgBook_Database_2018-10-04_22-49-41.sql.gz
9.1G	2018-10-04 23:17	/backups/daily/2018-10-04/wallet-db-tob_holder_2018-10-04_22-52-29.sql.gz
30G	2018-10-04 23:17	/backups/daily/2018-10-04
30G	2018-10-04 23:17	/backups/daily
30G	2018-10-04 23:17	/backups/
================================================================================================================================

Sleeping for 1d ...
```