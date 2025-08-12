# Overview

As a new user, I want to define all nodes, vservices, and related settings in a single yaml file (zpr-cert-info.yaml). A script/wizard walks me through creating the keys, a Docker override file and starts a toy ZPRnet. I want to easily verify that the ZPRnet is running and see its activity.

This repo includes dummy keys and certs in the `/authority` directory.

# Getting Started

## Requirements
- docker

## Commands

- Pull and run a simple network: `make up`


# Milestone 4


## Setup

For now you need to build stuff on a local ubuntu 24.04 linux machine in
order to get the correct code.  So do:

```bash
make build
make build-image
# above will fail with permission error, so then do:
sudo docker build -t alohagarage/zpr:m4
```


## Run the Demo

Then to start the container: `sudo make up`

The docker image starts three containers:
- Node
- Visa service plus adapter
- BAS plus adapter

The node exposes its docking port on the host OS at port `65000`. 


### Start VM, run the web service in it.

Now create a VM (make sure forwarding woks, etc) start a webserver on port 80
and connect the web adapter:

```bash
sudo ph adapter -d all -c authority/adapter-web-conf.toml
```

Note that the `node_addr` setting in the conf file above must be set to 
`<HOST-IP-ADDR>:65000`.

We assume in this doc that the web server has the rfc 0-500 collection.


### Connect as an Admin

From the guest OS you can now connect as the admin by pointing to the
`adapter-admin-conf.toml` file.  Eg:

```bash
sudo ph adapter -d all -c authority/adapter-admin-conf.toml
```  

And with that you will get privledges to talk to the visa service using
`vs-admin`.  Eg,


```bash
$ vs-admin -s https://\[fd5a:5052::1\]:8182 -c authority/auth-ca.crt actors
🐎 found 4 actors
vs.zpr (created: 2025-08-12T16:16:45Z) @ fd5a:5052::1
node.zpr.org (created: 2025-08-12T16:16:56Z) @ fd5a:5052:90de::1 [node]
bas.zpr.org (created: 2025-08-12T16:16:58Z) @ fd5a:5052:1:1::1
admin.zpr.org (created: 2025-08-12T16:17:30Z) @ fd5a:5052:1:1::2
```

Connected as the admin adapter you cannot access the web service.
So, for example, this will fail:

```bash
curl http://\[<ZPR-ADDRESS>\]/rfc1.txt
```

So kill the admin adapter on the host and re-connect as the "cli" adapter.


### Connect as a client

```bash
sudo ph adapter -d all -c authority/adapter-cli-conf.toml
```  

Now try the above `curl` command again and it should work.


