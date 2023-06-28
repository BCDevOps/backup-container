## Docker

This project contains a docker-compose.yml file suitable for development purposes. It will start a PostgreSQL database, minio (S3 compatible storage) and a backup container.

Because all the bash scripts are mounted to root `/` the docker-compose file mounts them all individually. If you wish to add new files, create it then add it to the backup container mounts. This method allows you to edit the files on the host and have changes immediately available in the container. You may need to restart the backup process to see the changes.

To start the containers run:

```bash
docker-compose up
```

Once all 3 containers start they will create three folders that are **not** tracked by git:

- `./pg-data` - PostgreSQL database
- `./minio-data` - Minio storage
- `./backup` - Backup data

Add this shell (bash or zsh) alias, it helps to quickly connect to a container by name:

```bash
dcon='function _dcon(){ docker exec -i -t $1 /bin/bash -c "export COLUMNS=`tput cols`; export LINES=`tput lines`; exec bash"; };_dcon'
```

Use `docker ps` to list all running containers and then use `dcon <container_name>` to connect to the container.

```bash
dcon backup-container-postgresql-1
```

### Protips 🤓

- More modern version fo docker-compose do not require the hyphen. Try using `docker compose up`.
- This bash one-liner was used to add all the files to the backup container volumes `ls docker/ | grep 'backup\.' | awk '{ print "- ./docker/"$1":/"$1 }'`

## Postgres

Connect to the postgres container using the `dcon` alias noted above and create the database, schema and then load in some sample data.

Connect to the postgres container:

```bash
dcon backup-container-postgresql-1
```

Run the `psql` command to connect to the database and create the database:

```bash
psql -U postgres
create database sakila;
^D
```

Run the following two commands to create the schema and insert the data. If `curl` is not installed run `apt-get update && apt-get install curl` first.

```bash
curl -sSL https://raw.githubusercontent.com/jOOQ/sakila/main/postgres-sakila-db/postgres-sakila-schema.sql | psql -U postgres -d sakila;
```

```bash
curl -sSL https://raw.githubusercontent.com/jOOQ/sakila/main/postgres-sakila-db/postgres-sakila-insert-data.sql | psql -U postgres -d sakila;
```

You should now have a sample database with data.
