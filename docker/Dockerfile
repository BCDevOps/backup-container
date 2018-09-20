# This image provides a postgres installation from which to run backups 
FROM registry.access.redhat.com/rhscl/postgresql-10-rhel7

# Set the workdir to be root
WORKDIR /

# Load the backup script into the container and make it executable
COPY backup.sh /
# RUN chmod -R a+rwx /backup.sh

# Set the default CMD to print the usage of the language image.
CMD sh /backup.sh

