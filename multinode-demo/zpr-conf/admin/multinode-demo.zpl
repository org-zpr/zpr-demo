
define OciWeb as a service.
define PremWeb as a service.

# `oci_user` and `prem_user` are tags set from trusted service.

allow oci_user users to access OciWeb.
allow prem_user users to access PremWeb.








