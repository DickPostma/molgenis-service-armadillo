package org.molgenis.armadillo.exceptions;

import static java.lang.String.format;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ResponseStatus;

@ResponseStatus(code = HttpStatus.NOT_FOUND)
public class UnknownProfileException extends RuntimeException {

  public UnknownProfileException(String profileName) {
    super(format("Profile: %s not found", profileName));
  }
}
