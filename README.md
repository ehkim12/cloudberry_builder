# eXperDB for Cloudberry Build
Docker를 통해 DBMS 빌드를 수행하고, 태그를 통해 버전별 형상관리를 합니다.

## Prerequisites
- docker(19.03 이상) [Get Started with Docker](https://www.docker.com/get-started/).
- Git, SSH, 외부 인터넷 연결



## 도커 패키지 빌드

When building and deploying Cloudberry in Docker, you will have 2 different deployment options as well as different build options.

**Deployment Options**
1. **Single Container** (Default) - With the single container option, you will have the coordinator as well as the Cloudberry segments all running on a single container. This is the default behavior when deploying using the `run.sh` script provided.
2. **Multi-Container** - Deploying with the multi-container option will give you a more realistic deployment of what actual production Cloudberry clusters look like. With multi-node, you will have the coordinator, the standby coordinator, and 2 segment hosts all on their own respective containers. This is to both highlight the distributed nature of Apache Cloudberry as well as highlight how high availability (HA) features work in the event of a server (or in this case a container) failing. This is enabled by passing the -m flag to the `run.sh` script which will be highlighted below.


**Build Options**

1. Compile with the source code of the latest Apache Cloudberry (released in [Apache Cloudberry Release Page](https://github.com/apache/cloudberry/releases)). The base OS will be Rocky Linux 9 Docker image.
2. Method 2 - Compile with the latest Apache Cloudberry [main](https://github.com/apache/cloudberry/tree/main) branch. The base OS will be Rocky Linux 9 Docker image.

- single container

```shell
cd bootcamp/000-cbdb-sandbox
./run.sh
```
- multiple container

```shell
cd bootcamp/000-cbdb-sandbox
./run.sh -m
```

## 데이터베이스 연결

> [!NOTE]
> When deploying the multi-container Cloudberry environment it may take extra time for the database to initialize, so you may need to wait a few minutes before you can execute the psql prompt successfully. You can run `docker logs cbdb-cdw -f` to see the current state of the database initialization process, you'll know the process is finished when you see the "Deployment Successful" output.

You can now connect to the database and try some basic operations.

1. Connect to the Docker container from the host machine:

    ```shell
    docker exec -it cbdb-cdw /bin/bash
    ```

    If it is successful, you will see the following prompt:

    ```shell
    [gpadmin@cdw /]$
    ```

2. Log into Apache Cloudberry in Docker. See the following commands and example outputs:

    ```shell
    [gpadmin@cdw ~]$ psql  # Connects to the database with the default database name "gpadmin".
    
    # psql (14.4, server 14.4)
    # Type "help" for help.
    ```

    ```sql
    gpadmin=# SELECT VERSION();  -- Checks the database version.
            
    PostgreSQL 14.4 (Apache Cloudberry 1.0.0 build dev) on aarch64-unknown-linux-gnu, compiled by gcc (GCC) 10.2.1 20210130 (Red Hat 10.2.1-11), 64-bit compiled on Oct 24 2023 10:24:28
    (1 row)
    ```

Now you have a Apache Cloudberry and can continue with [Apache Cloudberry Tutorials Based on Docker Installation](https://github.com/apache/cloudberry-bootcamp/blob/main/101-cbdb-tutorials/README.md)! Enjoy!

## Working with your Cloudberry Docker environment

When working with the Cloudberry Docker environment there are a few commands that will be useful to you.

**Stopping Your Single Container Deployment With Docker**

To stop the **single container** deployment while _keeping the data and state_ within the container, you can run the command below. This means that you can later start the container again and any changes you made to the containers will be persisted between runs.

```shell
docker stop cbdb-cdw
```

To stop the **single container** deployment and also remove the volume that belongs to the container, you can run the following command. Keep in mind this will remove the volume as well as the container associated which means any changes you've made inside of the container or any database state will be wiped and unrecoverable.

```shell
docker rm -f cbdb-cdw
```

**Stopping Your Multi-Container Deployment With Docker**

To stop the **multi-container** deployment while _keeping the data and state_ within the container, you can run the command below. This means that you can later start the container again and any changes you made to the containers will be persisted between runs.

```shell
docker compose -f docker-compose-rockylinux9.yml stop
```

To stop the **multi-container** deployment and also remove the network and volumes that belong to the containers, you can run the command below. Running this command means it will delete the containers as well as remove the volumes that the containers are associated with. This means any changes you've made inside of the containers or any database state will be wiped and unrecoverable.

```shell
docker compose -f docker-compose-rockylinux9.yml down -v
```

**Starting A Stopped Single Container Cloudberry Docker Deployment**

If you've run any of the commands above that keep the Docker volumes persisted between shutting the containers down, you can use the following commands to bring that same deployment back up with it's previous state.

To start a **single container** deployment after it was shut down, you can simply run the following

```shell
docker start cbdb-cdw
```

**Starting A Stopped Multi-Container Cloudberry Docker Deployment**

To start a **multi-container** deployment after it was shut down, you can run the following command.

```shell
docker compose -f docker-compose-rockylinux9.yml start
```

> [!NOTE]
> When starting a previously stopped Cloudberry Docker environment, you'll need to manually start the database back up. To do this, just run the following commands once the container(s) are back up and running. The `gpstart` command is used for starting the database, and -a is a flag saying to start the database without prompting (non-interactive).

```shell
docker exec -it cbdb-cdw /bin/bash

[gpadmin@cdw /] gpstart -a
```
