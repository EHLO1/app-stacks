# Basic Docker Server Setup (Ubuntu Server 22.04+)


## Overview
---
This guide will cover the basics on how to setup and configure an Ubuntu Server 22.04+ server for use with Docker workloads. The actual execution of Docker workloads will not be covered here.

## Requirements
---

###### Permissions
| Permission | Reason                                                               |
| ---------- | -------------------------------------------------------------------- |
| `sudo`     | Needed for installing packages and making changes to system folders. |
###### Knowledge
| Knowledge                 | Level          |
| ------------------------- | -------------- |
| Linux CLI                 | `Intermediate` |
| Linux Permissions         | `Intermediate` |
| Linux Directory Structure | `Intermediate` |

## Guide
---

> [!TIP] Use the /srv directory
> 
> It's not really used for anything anymore, but is almost always a default directory included in almost all Linux distros.

#### Install Docker

> [!WARNING] Use Docker's own documentation for installing Docker on a Linux Server: **https://docs.docker.com/engine/install/**

Follow the instructions provided in the link above to install Docker.


#### Create a docker user group

1. Create a docker group if it doesn't already exist:
	```shell
	sudo groupadd docker
	```
	<br>
2. Add yourself to the docker group (to run docker commands without sudo):
	```shell
	sudo usermod -aG docker $USER
	```
	<br>
3. Reload/Refresh group membership (if it doesn't work, log out or reboot):
	```shell
	sudo newgrp docker
	```  


#### Create the docker directory and set initial permissions

1. Create docker working directories:
	```shell
	sudo mkdir -p /srv/docker
	```
	<br>
2. Change ownership of docker directory:
	```shell
	sudo chown -R :docker /srv/docker
	```
	<br>
3. Change permissions of docker directory:
	```shell
	sudo chmod -R g+rwxs /srv/docker
	```


#### Install the acl package and configure the docker directory

1. Install the acl (Access Control List) package to auto-set permissions for the docker directory, as well as any newly created file or folder in that directory:
	```shell
	sudo apt install acl -y
	```
	<br>
2. Set acl permission for the docker directory:
	```shell
	sudo setfacl -R -m "d:g:docker:rwx" /srv/docker
	```


#### Create a subdirectory for any docker workload

> [!SUCCESS] You no longer need sudo when working in the /srv/docker directory.

For any given docker "application stack", create a subdirectory in the docker directory:
```shell
mkdir -p /srv/docker/app-name
```

> [!example] Example directory structure:
> 
> ```Directory-Structure
>/srv/docker/app-name
>	/data
>		/webserver-name (or reverse proxy, ex: caddy)
>			/config
>				config-file
>		/app-name
>			/config
>				config-file
>		/database-name
>			/config
>				config-file
> 	.env
> 	.gitignore
> 	docker-compose.yml
>```
