# --- build stage ---
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /app

# Better layer caching
COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline

COPY src ./src
RUN mvn -q -DskipTests package

# --- run stage ---
FROM eclipse-temurin:17-jre
WORKDIR /app

# App + debug port
EXPOSE 8080 5005

# Copy the built jar (artifactId = demodebug, version = 0.0.1-SNAPSHOT)
COPY --from=build /app/target/demodebug-0.0.1-SNAPSHOT.jar /app/app.jar

# Add entrypoint script for optional debug
COPY docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
