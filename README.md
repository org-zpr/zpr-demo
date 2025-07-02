# Overview

As a new user, I want to define all nodes, vservices, and related settings in a single yaml file (zpr-cert-info.yaml). A script/wizard walks me through creating the keys, a Docker override file and starts a toy ZPRnet. I want to easily verify that the ZPRnet is running and see its activity.

This repo includes dummy keys and certs in the `/authority` directory.

# Getting Started

## Requirements
- docker

## Commands

- Pull and run a simple network: `make up`
