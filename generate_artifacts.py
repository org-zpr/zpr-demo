import os
import sys
import subprocess
import argparse
from pathlib import Path

def run(command, shell=True):
    print(f"> {command}")
    result = subprocess.run(command, shell=shell)
    if result.returncode != 0:
        raise RuntimeError(f"Command failed: {command}")

def write_file(path, content):
    with open(path, "w") as f:
        f.write(content)

def is_client_adapter(name):
    return name.startswith("adapter") or name == "vs" or name == "web" or name == "cli" or name == "bas"

def generate_authority():
    authority_dir = Path("authority")
    authority_dir.mkdir(parents=True, exist_ok=True)
    run("openssl genrsa -aes256 -out authority/auth-ca.key 4096")
    run("openssl req -x509 -new -key authority/auth-ca.key -sha256 -days 1826 -out authority/auth-ca.crt")

def generate_zpr_rsa():
    run("openssl genrsa -out zpr-rsa-key.pem 2048")
    run("openssl req -new -key zpr-rsa-key.pem -out zpr.csr")

    sign_ext = """
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = DNS:*.zpr.org
"""
    write_file("sign.ext", sign_ext)

    run("openssl x509 -req -in zpr.csr -CA authority/auth-ca.crt -CAkey authority/auth-ca.key "
        "-CAcreateserial -out zpr-rsa.crt -days 1825 -sha256 -extfile sign.ext")

def generate_noise_keys_and_certs(node):
    priv_key = f"{node}-noise.key"
    pub_key = f"{node}-noise-pub.pem"
    cert = f"{node}-noise.crt"
    cn = "/CN=vs.zpr" if node == "vs" else f"/CN={node}.zpr.org"

    run(f"zpr-core/tools/zpr-pki genkey > {priv_key}")
    run(f"zpr-core/tools/zpr-pki pubkey < {priv_key} > {pub_key}")
    run(f"zpr-core/tools/zpr-pki gensignedcert authority/auth-ca.crt authority/auth-ca.key "
        f"{cn} 365 < {pub_key} > {cert}")

def generate_bootstrap_keys(node):
    priv_key = f"{node}-rsa-key.pem"
    pub_key = f"{node}-pubkey.pem"
    run(f"openssl genrsa -out {priv_key} 2048")
    run(f"openssl rsa -pubout -in {priv_key} -out {pub_key}")

def main():
    print("WARNING BROKEN - does not generate bas,web,cli,admin or bas keys FIXME")
    sys.exit(1)
    parser = argparse.ArgumentParser(description="Generate ZPRnet artifacts")
    parser.add_argument("--nodes", nargs="+", required=True, help="List of node names")
    args = parser.parse_args()

    generate_authority()
    generate_zpr_rsa()

    for node in args.nodes:
        generate_noise_keys_and_certs(node)
        if is_client_adapter(node):
            generate_bootstrap_keys(node)

if __name__ == "__main__":
    main()
