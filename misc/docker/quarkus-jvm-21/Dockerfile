FROM registry.access.redhat.com/ubi9/openjdk-21:1.22

ENV LANGUAGE='en_US:en'

EXPOSE 8080
USER 185
ENV JAVA_OPTS_APPEND="-Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager"
ENV JAVA_APP_JAR="/deployments/quarkus-run.jar"

RUN mkdir -p /tmp/logs && touch /tmp/logs/app.log

ENTRYPOINT [ "/opt/jboss/container/java/run/run-java.sh" ]