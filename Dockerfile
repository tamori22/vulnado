FROM eclipse-temurin:8-jdk

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential maven cowsay netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

COPY . .

CMD ["mvn", "spring-boot:run"]
