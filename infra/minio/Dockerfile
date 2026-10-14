FROM debian:bookworm-slim AS extract
COPY build/minio.deb /tmp/minio.deb
RUN echo "d8898351831761e083e7ba6b74ea7ec478b9a6680794fe92e5e838145341c9c5  /tmp/minio.deb" | sha256sum -c - \
    && dpkg-deb -x /tmp/minio.deb /out

FROM alpine:3.22
COPY --from=extract /out/usr/local/bin/minio /usr/local/bin/minio
RUN mkdir /data && chown 1000:1000 /data
USER 1000:1000
EXPOSE 9000 9001
ENTRYPOINT ["/usr/local/bin/minio"]
