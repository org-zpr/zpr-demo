import os
import yaml
import subprocess
from pathlib import Path

CONFIG_PATH = Path("zpr-cert-info.yaml")
OVERRIDE_PATH = Path("docker-compose.override.yml")
AUTH_DIR = Path("config/authority")

def run(cmd, **kwargs):
    print(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True, **kwargs)

def load_config():
    with open(CONFIG_PATH) as f:
        return yaml.safe_load(f)

def write_openssl_cnf(data):
    config = f"""[req]
distinguished_name = dn
prompt = no

[dn]
C = {data['ca']['country']}
ST = {data['ca']['state']}
L = {data['ca']['locality']}
O = {data['ca']['organization']}
OU = {data['ca']['organizational_unit']}
CN = {data['ca']['common_name']}
emailAddress = {data['ca']['email']}
"""
    Path("openssl.cnf").write_text(config)

def generate_authority(config):
    AUTH_DIR.mkdir(parents=True, exist_ok=True)
    os.chdir(AUTH_DIR)

    run(["openssl", "genrsa", "-aes256", "-out", "auth-ca.key", "4096"])
    run(["openssl", "req", "-x509", "-new", "-nodes", "-key", "auth-ca.key",
         "-sha256", "-days", "1826", "-out", "auth-ca.crt", "-config", "../../openssl.cnf"])

    run(["openssl", "genrsa", "-out", "zpr-rsa-key.pem", "2048"])
    run(["openssl", "req", "-new", "-key", "zpr-rsa-key.pem", "-out", "zpr.csr",
         "-config", "../../openssl.cnf"])

    with open("sign.ext", "w") as f:
        f.write("authorityKeyIdentifier=keyid,issuer\n")
        f.write("basicConstraints=CA:FALSE\n")
        f.write("keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment\n")
        f.write("subjectAltName = DNS:zpr.local\n")

    run(["openssl", "x509", "-req", "-in", "zpr.csr", "-CA", "auth-ca.crt",
         "-CAkey", "auth-ca.key", "-CAcreateserial", "-out", "zpr-rsa.crt",
         "-days", "1825", "-sha256", "-extfile", "sign.ext"])

    os.chdir("../../")

def generate_keys_and_override(config):
    services = config["services"]
    OVERRIDE_PATH.write_text("version: '3.9'\nservices:\n")

    for name, meta in services.items():
        service_dir = Path("config") / name
        keyfile = service_dir / f"{name}-noise.key"
        certfile = service_dir / f"{name}-noise.crt"
        pubfile = service_dir / f"{name}-noise-pub.pem"
        signext = service_dir / "sign.ext"

        service_dir.mkdir(parents=True, exist_ok=True)

        run([BIN_PATH, "genkey"], stdout=keyfile.open("w"))
        run([BIN_PATH, "pubkey"], stdin=keyfile.open(), stdout=pubfile.open("w"))

        signext.write_text(f"""authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = DNS:{meta['dns']}
""")

        run([
            "./bin/zpr-pki", "gensignedcert", "config/authority/auth-ca.crt",
            "config/authority/auth-ca.key", f"/CN={meta['dns']}", "365"
        ], stdin=pubfile.open(), stdout=certfile.open("w"))

        with OVERRIDE_PATH.open("a") as f:
            f.write(f"  {name}:\n    extra_hosts:\n")
            for peer, peer_meta in services.items():
                if peer != name:
                    f.write(f"      - \"{peer_meta['dns']}:{peer_meta['ip']}\"\n")

def main():
    config = load_config()
    write_openssl_cnf(config)
    generate_authority(config)
    generate_keys_and_override(config)
    print("✅ PKI and docker-compose.override.yml generated successfully.")

if __name__ == "__main__":
    main()
