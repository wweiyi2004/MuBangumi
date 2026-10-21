FROM dart:3.12@sha256:5ac89dbcae4327278b257920e2786df0f22c87adc630017266b67cfcceef8348 AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get --enforce-lockfile
COPY bin ./bin
COPY lib ./lib
COPY web ./web
RUN dart build cli --target bin/server.dart -o build

# Match the pinned Dart image's Debian distribution for the AOT runtime ABI.
FROM debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/* && useradd -r -u 10001 banjian && mkdir /data && chown banjian /data
WORKDIR /app
COPY --from=build /app/build/bundle/ ./
COPY web ./web
USER banjian
ENV BANJIAN_DATA=/data
EXPOSE 43928
CMD ["./bin/server"]
