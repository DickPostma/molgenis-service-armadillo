package org.molgenis.armadillo.metadata;

import static java.util.Collections.emptySet;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.molgenis.armadillo.profile.DockerService;
import org.molgenis.armadillo.storage.ArmadilloStorageService;

@ExtendWith(MockitoExtension.class)
class ArmadilloMetadataServiceTest {

  @Mock private ArmadilloStorageService storage;
  @Mock private DockerService dockerService;

  @Test
  void testBootstrapAdmin() {
    var loader = new DummyMetadataLoader();
    var metadataService =
        new ArmadilloMetadataService(storage, dockerService, loader, "bofke@gmail.com");
    metadataService.initialize();

    assertEquals(Boolean.TRUE, metadataService.userByEmail("bofke@gmail.com").getAdmin());
  }

  @Test
  void testBootstrapProjects() {
    var project1 = ProjectDetails.create("project1", emptySet());
    var project2 = ProjectDetails.create("project2", emptySet());
    var metadata =
        ArmadilloMetadata.create(
            new ConcurrentHashMap<>(),
            new ConcurrentHashMap<>(Map.of("project1", project1)),
            new ConcurrentHashMap<>(),
            emptySet());
    var loader = new DummyMetadataLoader(metadata);
    when(storage.listProjects()).thenReturn(List.of("project1", "project2"));

    var metadataService = new ArmadilloMetadataService(storage, dockerService, loader, null);
    metadataService.initialize();

    assertEquals(List.of(project2, project1), metadataService.projectsList());
  }
}
