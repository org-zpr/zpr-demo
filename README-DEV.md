# Overview - How to build a release

This describes how to use this repo to create a new release Note that this
requires access to all the relevant ZPR repositories.


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

Use a personal access token (classic) with the `write:packages` scope.  Login to ghcr:

    echo $TOKEN | sudo docker login ghcr.io -u <GITHUB_USER_NAME> --password-stdin

Then tag your local image:

    sudo docker tag org.zpr/zprdemo:<ZPR_IMAGE_VERSION> ghcr.io/org-zpr/zpr-demo/zprdemo:latest

And push:

    sudo docker push ghcr.io/org-zpr/zpr-demo/zprdemo:latest





## Test it

Launch the image with:

    sudo make up

After about 20s or so all three containers should be running: Node, Visa Serivice and BAS.


## Save your branch with correct name

Name your branch according to the convention, eg, `demo-20250922` and push it.



