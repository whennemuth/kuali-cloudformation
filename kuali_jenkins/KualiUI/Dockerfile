FROM adoptopenjdk/maven-openjdk11 AS SOURCE

WORKDIR /opt/jenkins-project

COPY src src/

COPY pom.xml .

RUN mvn package shade:shade

FROM adoptopenjdk/maven-openjdk11 AS PACKAGE

WORKDIR /opt

USER root

COPY --from=SOURCE /opt/jenkins-project/target/kuali-jenkins-ui.jar .

ENTRYPOINT [ "java", "-cp", "/opt/kuali-jenkins-ui.jar", "org.bu.jenkins.job.AbstractJob" ]


