FROM eclipse-temurin:17-jre

WORKDIR /app

ARG APP_VERSION

COPY user-service/target/user-service-${APP_VERSION}.jar app.jar

EXPOSE 8082

ENTRYPOINT ["java", "-jar", "app.jar"]