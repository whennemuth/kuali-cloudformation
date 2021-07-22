
FROM adoptopenjdk/maven-openjdk11 AS updated
WORKDIR /opt
USER root
ENV DEBIAN_FRONTEND=noninteractive
RUN \
  apt update; \
  apt install -y vim; \
  apt install -y git-all; \
  mkdir jenkins-scripts;



FROM updated AS SOURCE
USER root
WORKDIR /opt/jenkins-project
COPY src src/
COPY pom.xml .
RUN mvn package shade:shade



FROM updated AS PACKAGE
USER root
WORKDIR /opt
COPY utils.sh jenkins-scripts/
COPY --from=SOURCE /opt/jenkins-project/target/kuali-jenkins-ui.jar .
RUN [ ! -d /root/.ssh ] && mkdir /root/.ssh;

ENTRYPOINT [ "java", "-cp", "/opt/kuali-jenkins-ui.jar", "org.bu.jenkins.EntryPoint" ]


