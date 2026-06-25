define IoTDevice as an endpoint with zpr.adapter.cn:'ingress.zpr.org'
define OracleIoT as a service with endpoint.zpr.adapter.cn:'egress.zpr.org'

allow IoTDevice to access OracleIoT

