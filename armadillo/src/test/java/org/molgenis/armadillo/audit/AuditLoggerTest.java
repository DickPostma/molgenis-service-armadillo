package org.molgenis.armadillo.audit;

import static org.junit.jupiter.api.Assertions.*;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.io.StringWriter;
import java.time.Instant;
import java.util.Map;
import net.logstash.logback.marker.LogstashMarker;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.slf4j.Marker;
import org.springframework.boot.actuate.audit.AuditEvent;

class AuditLoggerTest {

  private AuditLogger auditLogger = new AuditLogger();
  private Logger logger = (Logger) LoggerFactory.getLogger(AuditLogger.class);
  private ObjectMapper objectMapper = new ObjectMapper();

  @Test
  void testJsonMarkers() throws IOException {
    ListAppender<ILoggingEvent> appender = new ListAppender<>();
    appender.start();
    logger.addAppender(appender);

    AuditEvent auditEvent =
        new AuditEvent(
            Instant.parse("2021-01-06T11:35:02.781470Z"),
            "principal",
            "TYPE",
            Map.of("detail", Map.of("foo", "bar")));
    auditLogger.onAuditEvent(auditEvent);

    appender.stop();
    logger.detachAppender(appender);
    assertEquals(1, appender.list.size());
    var loggingEvent = appender.list.get(0);
    assertEquals(
        "{\"timestamp\":\"2021-01-06T11:35:02.781470Z\",\"principal\":\"principal\",\"type\":\"TYPE\",\"data\":{\"detail\":{\"foo\":\"bar\"}}",
        writeMarkersToString(loggingEvent.getMarker()));
  }

  private String writeMarkersToString(Marker marker) throws IOException {
    var objectWriter = objectMapper.writer();
    var writer = new StringWriter();
    var generator = objectWriter.createGenerator(writer);
    generator.writeStartObject();
    ((LogstashMarker) marker).writeTo(generator);
    marker
        .iterator()
        .forEachRemaining(
            m -> {
              try {
                ((LogstashMarker) m).writeTo(generator);
              } catch (Exception ex) {
                throw new RuntimeException(ex);
              }
            });
    generator.writeEndObject();
    return writer.toString();
  }
}
