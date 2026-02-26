# Overview - How to build a release

This describes how to use this repo to create a new release Note that this
requires access to all the relevant ZPR repositories.


## Setup

The makefile will default to using todays date as the version number.


When you build a demo release it will use your host machine as the build
environment. You can optionaally use our development environment container
from the `zpr-dev-tools` repository.  To do so, make sure that the container
is available locally and tagged `zpr/dev-env:latest`, then pass
`USE_DOCKER=1` to all the make commands.

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

Or if using docker:

```bash
make USE_DOCKER=1 TAG=demo-VERSION release
```

NOTE: You can use `TAG=HEAD` to build from `main`.

Or you can run each make separately:
* `make TAG=demo-VERSION zprbins`
* `make creds`
* `make configs`
* `make policy`
* `make artifacts`
  * This creates a tgz archive of the ZPR binaries.


## Create the docker image

In the `docker/` subdirectory, run:

    sudo make build-image


This will tag the image with `ghcr.io/org-zpr/zpr-demo/zprdemo:latest`. You can
set the tag to anything you want, see `docker/Makefile` for hints.

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



