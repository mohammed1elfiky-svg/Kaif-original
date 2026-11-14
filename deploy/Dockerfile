# Image with the logics of Al-Kaif Al-Asli (the modules, reports and Java classes of this repository).
# It copies the jar into the volume of the lsFusion server at start (see compose.yaml) and exits.
FROM alpine:3.20

WORKDIR /logics
COPY kaif.jar ./kaif.jar
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
