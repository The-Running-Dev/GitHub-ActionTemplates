# Smallest image that serves HTTP, for the container workflow's self-test.
FROM busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e

ARG FIXTURE_TEXT=fixture-ok
COPY www/ /www/
RUN echo "$FIXTURE_TEXT" > /www/version.txt

EXPOSE 8080
HEALTHCHECK --interval=2s --timeout=2s --retries=5 CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1
CMD ["httpd", "-f", "-v", "-p", "8080", "-h", "/www"]
