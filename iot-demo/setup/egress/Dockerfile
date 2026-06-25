FROM ubuntu:24.04
RUN apt-get update && apt-get install -y mosquitto mosquitto-clients iproute2 && rm -rf /var/lib/apt/lists/*
COPY mosquitto.conf /etc/mosquitto/conf.d/zpr.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh
CMD ["/start.sh"]
