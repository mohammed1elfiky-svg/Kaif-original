# Web client of Al-Kaif Al-Asli: the lsFusion web client compiled with the Arabic texts
# (built by .github/workflows/web-client.yml, published as ghcr.io/<owner>/kaif:client)
FROM tomcat:9-jdk21
COPY ROOT.war ./webapps/ROOT.war
COPY ServerMessages_ar.properties ./lib/ServerMessages_ar.properties
