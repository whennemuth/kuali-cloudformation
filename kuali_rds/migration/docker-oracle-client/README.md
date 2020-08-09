## docker-oracle-client

A docker-container for Oracle Instant Client 12, based on CentOs. Perfect for using together with a dockerized oracle database, for instance [this one](https://github.com/biemond/docker-database-puppet).

### Steps:

1. **Load the docker image:**
   This repository may have a prebuilt docker image saved of as a tar.gz file.
   If so, it won't be necessary to built one as you can simply load it:
   `docker load < oracleclient.tar.gz`

   or...   

   **Build the docker image:**

   1. Unfortunately, Oracle does not allow us to include their software in docker-images, so you need to download Oracle Instant Client linux binaries (and accept their license) before we build the image.
      Get the following files:

      - oracle-instantclient12.2-basic-12.2.0.1.0-1.x86_64.rpm
      - oracle-instantclient12.2-devel-12.2.0.1.0-1.x86_64.rpm
      - oracle-instantclient12.2-sqlplus-12.2.0.1.0-1.x86_64.rpm

      from [here](https://www.oracle.com/database/technologies/instant-client/linux-x86-64-downloads.html) and place them in the same directory as the Dockerfile.

   2. Edit the tnsnames.ora file (Optional)
      Edit the included tnsnames.ora file, so you can conveniently access these databases from the container, without having to enter the entire connection string. 

   3. Build the image
      `docker build -t oracle/oracleclient .`

   4. Save the image (optional)
      So that you can share this repository with others and not require them to find the oracle binaries and build the docker image, save the image off as a compressed file. They can simply run the docker load command as detailed above and skip to step 2.
      `docker save oracle/oracleclient | gzip > oracleclient.tar.gz`

2. **Run the image:**
   If you are running a dockerized database, pass its reference in via a docker link:
   `docker run -it --name oracleclient --link oracle:oracle oracle/oracleclient`
   Otherwise, you can run it without the link, and connect to other databases via a connection string.
   `docker run -it --name oracleclient oracle/oracleclient`

3. **Verify that it works:**
   `sqlplus sys/Welcome01@oracle`