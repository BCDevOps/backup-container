# Tips and Tricks

## Verify Fails with - `error connecting to db server` or simular message

### Issue

The postgres and mongo containers used for the backup container have the following (simplified) startup sequence for the database server:
- Start the server to perform initial server and database configuration.
- Shutdown the server.
- Start the server with the created configuration.

If memory and CPU requests and limits have been set for the container it is possible for this sequence to be slowed down enough that the `pingDbServer` operation will return success during the initial startup and configuration, and the subsequent `restoreDatabase` operation will run while the database server is not running (before it's started the second time).

### Example Logs

For a Mongo backup-container the error looks like this:
```
sh-4.2$ ./backup.sh -s -v all

Verifying backup ...

Settings:
- Database: mongo=identity-kit-db-bc/identity_kit_db
- Backup file: /backups/daily/2020-03-06/identity-kit-db-bc-identity_kit_db_2020-03-06_01-00-00.sql.gz

waiting for server to start....
Restoring from backup ...
2020-03-06T07:28:31.299-0800 W NETWORK  [thread1] Failed to connect to 127.0.0.1:27017, in(checking socket for error after poll), reason: Connection refused
2020-03-06T07:28:31.299-0800 E QUERY    [thread1] Error: couldn't connect to server 127.0.0.1:27017, connection attempt failed :
connect@src/mongo/shell/mongo.js:251:13
@(connect):1:21
exception: connect failed
Cleaning up ...

rm: cannot remove '/var/lib/mongodb/data/journal': Directory not empty
[!!ERROR!!] - Backup verification failed: /backups/daily/2020-03-06/identity-kit-db-bc-identity_kit_db_2020-03-06_01-00-00.sql.gz

The following issues were encountered during backup verification;
Restoring '/backups/daily/2020-03-06/identity-kit-db-bc-identity_kit_db_2020-03-06_01-00-00.sql.gz' to '127.0.0.1/identity_kit_db' ...

2020-03-06T07:28:30.785-0800    Failed: error connecting to db server: no reachable servers

Restore failed.

Elapsed time: 0h:0m:16s - Status Code: 1
```


### Solution

Configure the `backup-container` to use best effort resource allocation.  **This IS the default for the supplied deployment configuration template**; [backup-deploy.json](../openshift/templates/backup/backup-deploy.json)

Best effort resource allocation can only be set using a template or by directly editing the DC's yaml file.

The resources section in the containers template in the resulting DC looks like this:
```
apiVersion: apps.openshift.io/v1
kind: DeploymentConfig
...
spec:
  ...
  template:
    ...
    spec:
      containers:
        ...
          resources:
            limits:
              cpu: '0'
              memory: '0'
            requests:
              cpu: '0'
              memory: '0'
...
```