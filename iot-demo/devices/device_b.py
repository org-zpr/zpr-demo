"""
Device B — CO2 & Pressure simulator.
To swap in real hardware, replace read_sensors() with actual hardware reads.
"""

import json
import os
import random
import time
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

BROKER_HOST = os.environ.get("MQTT_BROKER_HOST", "localhost")
BROKER_PORT = int(os.environ.get("MQTT_BROKER_PORT", "8883"))
TOPIC = os.environ.get("MQTT_TOPIC", "devices/device-b/telemetry")
PUBLISH_INTERVAL = float(os.environ.get("PUBLISH_INTERVAL", "5"))
CA_CERT = os.environ.get("MQTT_CA_CERT")
BIND_ADDRESS = os.environ.get("BIND_ADDRESS", "")

DEVICE_ID = "device-b"
SENSOR_TYPE = "co2_pressure"


def read_sensors():
    return {
        "co2_ppm": round(random.uniform(400.0, 800.0), 1),
        "pressure_hpa": round(random.uniform(1000.0, 1020.0), 2),
    }


def main():
    client = mqtt.Client(client_id=DEVICE_ID)
    if CA_CERT:
        client.tls_set(ca_certs=CA_CERT)
    client.connect(BROKER_HOST, BROKER_PORT, bind_address=BIND_ADDRESS)
    client.loop_start()

    print(f"[{DEVICE_ID}] Connected to {BROKER_HOST}:{BROKER_PORT}, publishing to {TOPIC}")

    while True:
        payload = {
            "device_id": DEVICE_ID,
            "sensor_type": SENSOR_TYPE,
            "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            **read_sensors(),
        }
        client.publish(TOPIC, json.dumps(payload))
        print(f"[{DEVICE_ID}] {payload}")
        time.sleep(PUBLISH_INTERVAL)


if __name__ == "__main__":
    main()
