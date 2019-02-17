FROM debian:testing
USER root

ADD debian-rebuild.sh /
RUN chmod +x /debian-rebuild.sh
RUN /debian-rebuild.sh
