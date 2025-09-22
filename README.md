# Overview

This repo contains scripts to create a zpr demo release which includes a docker
container running the core services, plus a couple of adapter configuration
files to enable connectivity into the container.


**How to build a release** describes how to use this repo to create a new release
Note that this requires access to all the relevant ZPR repositories.

**How to run the demo** describes how to get the demo running using pre-built
configurations and binaries.




# How to build a release

## Setup

The makefile will default to using todays date as the version number.

For now you need to build stuff on a local ubuntu 24.04 linux machine in
order to get the correct code.

You need to first tag all these repos with a tag like `demo-VERSION`:
* `zpr-core`
* `zpr-compiler`
* `zpr-visaservice`
* `zpr-bas`

Also verify that the `POLICY` variable in the makefile is set to the correct
ZPL file.


## Build everything

```bash
make TAG=demo-VERSION release
```

Or you can run each make separately:
* `make TAG=demo-VERSION zprbins`
* `make creds` -- You will be prompted during creating of certificates.
  * The first passpharse you enter is for the local certificate authority. You will need to enter this every time we create a certificate.
  * Certificate 1 is for the CA itself.  Typical CN value is `auth.zpr`.
  * Certificate 2 is for the ZPR keypair.  Typical CN value is `root.zpr`. No need for a challenge password or optional company name.
  * Certificate 3 is for TLS connection to bas.  Use CN of `bas.zpr.org`.
* `make configs`
* `make policy`
* `make artifacts`
  * This creates a tgz archive of the ZPR binaries.


## Create the docker image

In the `docker/` subdirectory, run:

    sudo make build-image

This will tag the image with `root_VERSION`.  `VERSION` defaults to todays date. See `docker/Makefile` for
how to override this.


## Test it

Launch the image with:

    sudo make up

After about 20s or so all three containers should be running: Node, Visa Serivice and BAS.


## Save your branch

TODO: Current idea is to keep branches for each demo version.  Maybe also merge latest to main?

So name your branch according to the convention, eg, `demo-20250922` and push it.



# How to run the demo

To run the demo you need three things:

1. The docker container.
2. The release configuration.
3. The release binaries.

All three components must have the same version. The version is a timestamp
in `YYYYMMDD` format.  For example, `20250919`.

You can find the docker image in **TBD**.

The release configuration will be in this repo in a [branch](https://github.com/org-zpr/zpr-demo/branches)
named `demo-VERSION`, where `VERSION` is the version number.

The release binaries can be found in this repo in the [releases](https://github.com/org-zpr/zpr-demo/releases)
section using the same `demo-VERSION` naming convention.



## Run the Demo

Using the correct branch of this repo.

Get the correct binaries from the github *releases* section.


### Get and Launch the Docker container.

TODO: How to find the docker image?
TODO: How to run it? I presume you still need the compose file?

Then to start the container: `sudo make up`

The docker image starts three containers:
- Node
- Visa service plus adapter
- BAS plus adapter

The node exposes its docking port on the host OS at port `65000`. The config
files for the "cli", "admin", and "web" adapters (all in the `authority/`
directory) are setup with the `node_addr` set to `127.0.0.1:65000` -- that is
correct only if connecting from the host OS. Connecting from a VM or whereever
will require overriding that value.


### Start VM, run the web service in it.

Now create a VM (make sure forwarding woks, etc) start a webserver on port 80
and connect the web adapter:

```bash
sudo ph adapter -l all=DEBUG -c release/conf/adapter-web-conf.toml
```

Note that the `node_addr` setting in the conf file above must be set to
`<HOST-IP-ADDR>:65000`.

We assume in this doc that the web server has the rfc 0-500 collection.


### Connect as an Admin

From the host OS you can now connect as the admin by pointing to the
`adapter-admin-conf.toml` file.  Eg:

```bash
sudo ph adapter -l all=DEBUG -c release/conf/adapter-admin-conf.toml
```

And with that you will get privileges to talk to the visa service using
`vs-admin`.  Eg,


```bash
$ vs-admin -s https://\[fd5a:5052::1\]:8182 -c release/conf/auth-ca.crt actors
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
sudo ph adapter -l all=DEBUG -c release/conf/adapter-cli-conf.toml
```

Now try the above `curl` command again and it should work.


