package org.molgenis.armadillo.controller;

import static org.molgenis.armadillo.audit.AuditEventPublisher.COPY_OBJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.CREATE_PROJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.DELETE_OBJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.DELETE_PROJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.DOWNLOAD_OBJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.GET_OBJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.GET_PROJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.LIST_OBJECTS;
import static org.molgenis.armadillo.audit.AuditEventPublisher.LIST_PROJECTS;
import static org.molgenis.armadillo.audit.AuditEventPublisher.MOVE_OBJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.OBJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.PROJECT;
import static org.molgenis.armadillo.audit.AuditEventPublisher.UPLOAD_OBJECT;
import static org.springframework.http.HttpHeaders.CONTENT_DISPOSITION;
import static org.springframework.http.HttpStatus.NO_CONTENT;
import static org.springframework.http.HttpStatus.OK;
import static org.springframework.http.MediaType.APPLICATION_JSON_VALUE;
import static org.springframework.http.MediaType.APPLICATION_OCTET_STREAM;
import static org.springframework.http.MediaType.MULTIPART_FORM_DATA_VALUE;
import static org.springframework.http.ResponseEntity.noContent;
import static org.springframework.http.ResponseEntity.notFound;
import static org.springframework.web.bind.annotation.RequestMethod.HEAD;

import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.io.IOException;
import java.security.Principal;
import java.util.List;
import java.util.Map;
import javax.validation.Valid;
import org.molgenis.armadillo.audit.AuditEventPublisher;
import org.molgenis.armadillo.exceptions.FileProcessingException;
import org.molgenis.armadillo.storage.ArmadilloStorageService;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@Tag(name = "storage", description = "API to manipulate the storage")
@RestController
@Valid
@SecurityRequirement(name = "http")
@SecurityRequirement(name = "bearerAuth")
@SecurityRequirement(name = "JSESSIONID")
@RequestMapping("storage")
public class StorageController {

  private final ArmadilloStorageService storage;
  private final AuditEventPublisher auditor;

  public StorageController(ArmadilloStorageService storage, AuditEventPublisher auditor) {
    this.storage = storage;
    this.auditor = auditor;
  }

  @GetMapping("/projects")
  @ResponseStatus(OK)
  public List<String> listProjects(Principal principal) {
    return auditor.audit(storage::listProjects, principal, LIST_PROJECTS, Map.of());
  }

  @PostMapping(
      value = "/projects",
      consumes = {APPLICATION_JSON_VALUE})
  @ResponseStatus(NO_CONTENT)
  public void createProject(Principal principal, @RequestBody ProjectRequestBody project) {
    auditor.audit(
        () -> storage.createProject(project.name()),
        principal,
        CREATE_PROJECT,
        Map.of(PROJECT, project.name()));
  }

  @RequestMapping(value = "/projects/{project}", method = HEAD)
  public ResponseEntity<Void> projectExists(Principal principal, @PathVariable String project) {
    var projectExists =
        auditor.audit(
            () -> storage.hasProject(project), principal, GET_PROJECT, Map.of(PROJECT, project));
    return projectExists ? noContent().build() : notFound().build();
  }

  @DeleteMapping("/projects/{project}")
  @ResponseStatus(NO_CONTENT)
  public void deleteProject(Principal principal, @PathVariable String project) {
    auditor.audit(
        () -> storage.deleteProject(project), principal, DELETE_PROJECT, Map.of(PROJECT, project));
  }

  @GetMapping("/projects/{project}/objects")
  @ResponseStatus(OK)
  public List<String> listObjects(Principal principal, @PathVariable String project) {
    return auditor.audit(
        () -> storage.listObjects(project), principal, LIST_OBJECTS, Map.of(PROJECT, project));
  }

  @PostMapping(
      value = "/projects/{project}/objects",
      consumes = {MULTIPART_FORM_DATA_VALUE})
  @ResponseStatus(NO_CONTENT)
  public void uploadObject(
      Principal principal, @PathVariable String project, @RequestParam MultipartFile file) {
    auditor.audit(
        () -> addObject(project, file), principal, UPLOAD_OBJECT, Map.of(PROJECT, project));
  }

  private void addObject(String project, MultipartFile file) {
    try {
      storage.addObject(project, file.getOriginalFilename(), file.getInputStream());
    } catch (IOException e) {
      throw new FileProcessingException();
    }
  }

  @PostMapping(
      value = "/projects/{project}/objects/{object}/copy",
      consumes = {APPLICATION_JSON_VALUE})
  @ResponseStatus(NO_CONTENT)
  public void copyObject(
      Principal principal,
      @PathVariable String project,
      @PathVariable String object,
      @RequestBody ObjectRequestBody requestBody) {
    auditor.audit(
        () -> storage.copyObject(project, requestBody.name(), object),
        principal,
        COPY_OBJECT,
        Map.of(PROJECT, project, "from", object, "to", requestBody.name()));
  }

  @PostMapping(
      value = "/projects/{project}/objects/{object}/move",
      consumes = {APPLICATION_JSON_VALUE})
  @ResponseStatus(NO_CONTENT)
  public void moveObject(
      Principal principal,
      @PathVariable String project,
      @PathVariable String object,
      @RequestBody ObjectRequestBody requestBody) {
    auditor.audit(
        () -> storage.moveObject(project, requestBody.name(), object),
        principal,
        MOVE_OBJECT,
        Map.of(PROJECT, project, "from", object, "to", requestBody.name()));
  }

  @RequestMapping(value = "/projects/{project}/objects/{object}", method = HEAD)
  public ResponseEntity<Void> objectExists(
      Principal principal, @PathVariable String project, @PathVariable String object) {
    var objectExists =
        auditor.audit(
            () -> storage.hasObject(project, object),
            principal,
            GET_OBJECT,
            Map.of(PROJECT, project, OBJECT, object));
    return objectExists ? noContent().build() : notFound().build();
  }

  @DeleteMapping("/projects/{project}/objects/{object}")
  @ResponseStatus(NO_CONTENT)
  public void deleteObject(
      Principal principal, @PathVariable String project, @PathVariable String object) {
    auditor.audit(
        () -> storage.deleteObject(project, object),
        principal,
        DELETE_OBJECT,
        Map.of(PROJECT, project, OBJECT, object));
  }

  @GetMapping("/projects/{project}/objects/{object}")
  public @ResponseBody ResponseEntity<ByteArrayResource> downloadObject(
      Principal principal, @PathVariable String project, @PathVariable String object) {
    return auditor.audit(
        () -> getObject(project, object),
        principal,
        DOWNLOAD_OBJECT,
        Map.of(PROJECT, project, OBJECT, object));
  }

  private ResponseEntity<ByteArrayResource> getObject(String project, String object) {
    var inputStream = storage.loadObject(project, object);
    var objectParts = object.split("/");
    var fileName = objectParts[objectParts.length - 1];

    try {
      var resource = new ByteArrayResource(inputStream.readAllBytes());
      return ResponseEntity.ok()
          .header(CONTENT_DISPOSITION, "attachment; filename=" + fileName)
          .contentLength(resource.contentLength())
          .contentType(APPLICATION_OCTET_STREAM)
          .body(resource);
    } catch (IOException e) {
      throw new FileProcessingException();
    }
  }
}
