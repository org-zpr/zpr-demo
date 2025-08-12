#!/bin/sh

# Docker compose will start node and visa service
# before starting this.  Visa service has some timeouts
# in it to wait on the node.  For bas to work both node
# and VS must be up and fully connected.

# XXX wait for node+vs to intialize
echo "BAS waiting 20s for node+vs to set up"
sleep 20


mkdir -p /var/run/zpr

# We can bring up the BAS without a ZPR addr.
# So no need to set up TUN.
# TODO: Requires patch in mk/m4 branch.



# The image should already have the bas database set up.
# It must be in a directory named "db" in cwd.

# Dockerfile sets up 
# /app/db and /app/certs

echo "BAS launching the bas service"
cd /app
exec ./bin/bas serve --key certs/tlskey.key --cert certs/tlscert.crt &
cd ..

sleep 1

# Then start the adapter
echo "BAS starting bas adapter"
exec /app/bin/ph adapter -c /authority/adapter-bas-conf.toml --debug all




