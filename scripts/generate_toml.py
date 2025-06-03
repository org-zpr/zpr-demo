from pathlib import Path
import toml

def generate_toml(service_name, service_info, ca_file, cert_file, key_file, is_adapter=False):
    config = {
        "global": {
            "name": service_name,
            "ca_file": ca_file,
            "certificate_file": cert_file,
            "private_key_file": key_file,
            "self_addr": f"{service_info['ip']}:5000",
            "zpr_addr": [service_info.get("zpr_addr", "::1")],
            "tun_if": "tun9",
        }
    }

    if is_adapter:
        config["adapter"] = {
            "node_addr": service_info.get("node_addr", "172.28.0.2:5000"),
            "node_public_key_file": service_info.get("node_pub_file", "node-noise-pub.pem")
        }

    return toml.dumps(config)

# Example usage:
if __name__ == "__main__":
    example = {
        "ip": "172.28.0.3",
        "dns": "adapter-visa.zpr",
        "type": "adapter",
        "node_addr": "172.28.0.2:5000"
    }
    toml_str = generate_toml("adapter-visa", example,
                             "auth-ca.crt", "adapter-visa-noise.crt", "adapter-visa-noise.key", True)
    Path("example-adapter.toml").write_text(toml_str)
