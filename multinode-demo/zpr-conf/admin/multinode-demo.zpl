
define OciWeb as a service.
define PremWeb as a service.

allow location:oci users to access OciWeb.
allow location:onprem users to access PremWeb.

allow role:admin users to access OciWeb.
allow role:admin users to access PremWeb.







