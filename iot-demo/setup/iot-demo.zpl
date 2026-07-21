define DeviceA as an endpoint with zpr.adapter.cn:'device-a.zpr.org'
define OracleIoT as a service with endpoint.zpr.adapter.cn:'egress.zpr.org'

allow DeviceA to access OracleIoT

