FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart build cli --target bin/server.dart -o build

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/* && useradd -r -u 10001 banjian && mkdir /data && chown banjian /data
WORKDIR /app
COPY --from=build /app/build/bundle/ ./
COPY web ./web
USER banjian
ENV BANJIAN_DATA=/data
EXPOSE 43928
CMD ["./bin/server"]
