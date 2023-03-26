FROM eclipse-temurin:17-jdk-focal
ARG JAR_FILE
EXPOSE 8080
COPY ${JAR_FILE} molgenis-armadillo.jar
ENTRYPOINT ["java","-jar","molgenis-armadillo.jar"]
