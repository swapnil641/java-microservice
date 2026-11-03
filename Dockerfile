FROM eclipse-temurin:17-jre

WORKDIR /app

ARG APP_VERSION

COPY target/java-microservice-${APP_VERSION}.jar app.jar

EXPOSE 8081

ENTRYPOINT ["java", "-jar", "app.jar"]
