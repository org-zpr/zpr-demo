# Multinode Demo

See `README.md`
See `../AGENTS.md`

High level plan for this multinode demo: `PLAN.md`

Sub plans are in `work/` directory - in order of completion:

1. `work/tf-setup-plan.md` - DONE
2. `work/tf-no-vs-plan.md` - DONE
3. `work/tf-configure-run-zpr.md` - DONE
4. `work/docker-configure-run-zpr.md` (§5–8, local docker env) - DONE
5. `work/docker-configure-run-zpr-steps.md` - DONE
6. `work/endpoint-to-device-plan.md` - DONE
7. `work/scripts-plan.md` + `work/scripts-steps.md` (operator commands in `commands/`) - DONE
8. `work/use-zpr-dashboard-plan.md` (`zpr-dashboard` TUI + `commands/demo-zpr-dashboard`) - DONE
9. `work/hosts-files.md` (admin host `/etc/hosts` for `premweb.demo` / `ociweb.demo`) - DONE
10. `work/fetcher.md` - DONE
11. `work/regen-banner.md` - DONE



## Tools

* The OCI command line tool is installed and configured with access to our
  OCI tenancy/compartment.  See `oci --help` for help.

* OpenTofu is installed. See `tofu --help` for help.

* Docker is installed.  See `docker --help`.
