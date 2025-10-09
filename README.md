# ZPR Demo

This repository contains support files for the containerized ZPR Demo as well as
configuration and scripts used to create new versions of the demo.

The rest of this file is about running the demo.  If you need to build a new release see
[README-DEV.md](https://github.com/org-zpr/zpr-demo/blob/main/README-DEV.md).


# Latest Demo Release

The latest release will be here in `main` and in a branch named `demo-YYYYMMDD`.

The demo consists of a container image, some binaries and some configuration
files.

- The container image can be downloaded from GHCR in the [org-zpr packages area](https://github.com/orgs/org-zpr/packages/container/package/zpr-demo%2Fzprdemo).
- The release binaries are in the [releases area](https://github.com/org-zpr/zpr-demo/releases).
- The configuration files are in the repo in [release/conf](https://github.com/org-zpr/zpr-demo/tree/main/release/conf).


# How to run the demo

To run the demo you need three things:

1. The docker container.
2. The release configuration.
3. The release binaries.

All three components must have the same version. The version is a timestamp
in `YYYYMMDD` format.  For example, `20250919`.

You can find the docker image in the [org-zpr packages area](https://github.com/orgs/org-zpr/packages/container/package/zpr-demo%2Fzprdemo).

The release configuration will be in this repo in a [branch](https://github.com/org-zpr/zpr-demo/branches)
named `demo-VERSION`, where `VERSION` is the version number.

The release binaries can be found in this repo in the [releases](https://github.com/org-zpr/zpr-demo/releases)
section using the same `demo-VERSION` naming convention.



## Run the Demo

Using the correct branch of this repo.

Get the correct binaries from the github *releases* section.


### Get and Launch the Docker container.

Then to start the container: `sudo make ZPR_IMAGE_VERSION=latest up`

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


