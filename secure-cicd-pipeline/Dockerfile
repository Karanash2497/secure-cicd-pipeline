# ── Stage 1: Build ────────────────────────────────────────────────────────────
# Use full JDK only for compilation; never ships in the final image
FROM maven:3.9-eclipse-temurin-21-alpine AS build

WORKDIR /build

# Cache Maven deps before copying source (speeds up rebuilds)
COPY app/pom.xml .
RUN mvn dependency:go-offline -q

# Copy source and build fat JAR
COPY app/src ./src
RUN mvn package -DskipTests -q

# ── Stage 2: Runtime ───────────────────────────────────────────────────────────
# Minimal JRE-only Alpine image — far fewer CVEs than full JDK on Ubuntu
FROM eclipse-temurin:21-jre-alpine

# Security: create a non-root user/group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy only the compiled JAR from build stage
COPY --from=build /build/target/*.jar app.jar

# Security: drop to non-root before starting the process
USER appuser

EXPOSE 8080

# Use exec form (not shell form) so signals pass correctly to Java process
ENTRYPOINT ["java", "-jar", "app.jar"]
