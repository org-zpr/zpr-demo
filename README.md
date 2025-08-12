# Overview

As a new user, I want to define all nodes, vservices, and related settings in a single yaml file (zpr-cert-info.yaml). A script/wizard walks me through creating the keys, a Docker override file and starts a toy ZPRnet. I want to easily verify that the ZPRnet is running and see its activity.

This repo includes dummy keys and certs in the `/authority` directory.

# Getting Started

## Requirements
- docker

## Commands

- Pull and run a simple network: `make up`


# Milestone 4

The docker image starts three containers:
- Node
- Visa service plus adapter
- BAS plus adapter

The node exposes its docking port on the host OS at port `65000`. 

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

TODO: Create a local VM and start a web service
TODO: Then connect as the client and talk to the web service
