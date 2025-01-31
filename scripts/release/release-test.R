cat("
  __  __  ____  _      _____ ______ _   _ _____  _____                                     _ _ _ _
 |  \\/  |/ __ \\| |    / ____|  ____| \\ | |_   _|/ ____|     /\\                            | (_) | |
 | \\  / | |  | | |   | |  __| |__  |  \\| | | | | (___      /  \\   _ __ _ __ ___   __ _  __| |_| | | ___
 | |\\/| | |  | | |   | | |_ |  __| | . ` | | |  \\___ \\    / /\\ \\ | '__| '_ ` _ \\ / _` |/ _` | | | |/ _ \\
 | |  | | |__| | |___| |__| | |____| |\\  |_| |_ ____) |  / ____ \\| |  | | | | | | (_| | (_| | | | | (_) |
 |_|  |_|\\____/|______\\_____|______|_| \\_|_____|_____/  /_/    \\_\\_|  |_| |_| |_|\\__,_|\\__,_|_|_|_|\\___/

  _____      _                       _            _
 |  __ \\    | |                     | |          | |
 | |__) |___| | ___  __ _ ___  ___  | |_ ___  ___| |_
 |  _  // _ \\ |/ _ \\/ _` / __|/ _ \\ | __/ _ \\/ __| __|
 | | \\ \\  __/ |  __/ (_| \\__ \\  __/ | ||  __/\\__ \\ |_
 |_|  \\_\\___|_|\\___|\\__,_|___/\\___|  \\__\\___||___/\\__|
")
# for logging nicely and showing loading spinner
library(cli)
cli_h1("Setup")
cli_alert_info("Loading libraries")
# for password prompt
library(getPass)
# for reading parquet files
library(arrow)
# for doing api calls
library(httr)
# for loading json to put to api
library(jsonlite)
# to post resource file async to server to be able to show spinner while loading
library(future)
# to test if url exists
library(RCurl)
# to generate random project names
library(stringi)
# armadillo/datashield libraries needed for testing
library(MolgenisArmadillo)
library(DSI)
library(dsBaseClient)
library(DSMolgenisArmadillo)
library(resourcer)

# set when admin password given + question answered with y
update_auto = ""
do_run_spinner <- TRUE
ADMIN_MODE <- FALSE

# default profile settings in case a profile is missing
profile_defaults = data.frame(
  name = c("xenon", "rock"),
  container = c("datashield/armadillo-rserver_caravan-xenon:1.0.0", "datashield/rock-base:latest"),
  port = c("", 8085),
  # Multiple packages can be concattenated using ,, then using stri_split_fixed() to break them up again
  # Not adding dsBase since that is always(?) required
  whitelist = c("resourcer", ""),
  blacklist = c("", "")
)

exit_test <- function(msg){
  cli_alert_danger(msg)
  cond = structure(list(message=msg), class=c("exit", "condition"))
  signalCondition(cond)
}

create_bearer_header <- function(token){
  return(paste0("Bearer ", token))
}

create_basic_header <- function(pwd){
  encoded <- base64enc::base64encode(
    charToRaw(
      paste0("admin:", pwd))
  )
  return(paste0("Basic ", encoded))
}

# make authentication header for api calls, basic or bearer based on type
get_auth_header <- function(type, key){
  header_content <- ""
  if(tolower(type) == "bearer"){
    header_content <- create_bearer_header(key)
  } else if(tolower(type) == "basic") {
    header_content <- create_basic_header(key)
  } else {
    exit_test(sprintf("Type [%s] invalid, choose from 'basic' and 'bearer'"))
  }
  return(c("Authorization" = header_content))
}

# armadillo api put request
put_to_api <- function(endpoint, key, auth_type, body_args){
  auth_header <- get_auth_header(auth_type, key)
  body <- jsonlite::toJSON(body_args, auto_unbox=TRUE)
  response <- PUT(paste0(armadillo_url, endpoint), body=body, encode="json",
                  config = c(httr::content_type_json(), httr::add_headers(auth_header)))
  return(response)
}

spin_till_done <- function(spinner){
    # run_spinner is a boolean set on top of this script, it is set to false when loading is done and spinner can stop
    if (do_run_spinner) {
        Sys.sleep(0.1)
    } else {
        spinner$finish()
    }
}

run_spinner <- function(spinner) {
  lapply(1:1000, function(x) { spinner$spin(); spin_till_done(spinner)})
}

# post resource to armadillo api
post_resource_to_api <- function(project, key, auth_type, file, folder, name){
  auth_header <- get_auth_header(auth_type, key)
  plan(multisession)
  spinner <- make_spinner()
  # Do async call
  api_call <- future(POST(sprintf("%sstorage/projects/%s/objects", armadillo_url, project),
    body=list(file = file, object=paste0(folder,"/", name)),
                    config = c(httr::add_headers(auth_header))))

  # Run spinner while waiting for response
  ansi_with_hidden_cursor(run_spinner(spinner))
  # Response will come when ready
  response <- value(api_call)
  # Set do_run_spinner to false, causing the spinner to stop running, see spin_till_done method
  do_run_spinner <- FALSE
  if(response$status_code != 204) {
    cli_alert_warning(sprintf("Could not upload [%s] to project [%s]", name, project))
    exit_test(content(response)$message)
  }
}

# get request to armadillo api without authentication
get_from_api <- function(endpoint) {
  cli_alert_info(sprintf("Retrieving [%s%s]", armadillo_url, endpoint))
  response <- GET(paste0(armadillo_url, endpoint))
  return(content(response))
}

# get request to armadillo api with an authheader
get_from_api_with_header <- function(endpoint, key, auth_type){
  auth_header <- get_auth_header(auth_type, key)
  response <- GET(paste0(armadillo_url, endpoint), config = c(httr::add_headers(auth_header)))
  if(response$status_code == 403){
    msg <- sprintf("Permission denied. Is user [%s] admin?", user)
    exit_test(msg)
  } else if(response$status_code != 200) {
    cli_alert_danger(sprintf("Cannot retrieve data from endpoint [%s]", endpoint))
    exit_test(content(response)$message)
  }
  return(content(response))
}

# add/edit user using armadillo api
set_user <- function(user, admin_pwd, isAdmin, project1, omics_project){
  args <- list(email = user, admin = isAdmin, projects= list(project1, omics_project))
  response <- put_to_api("access/users", admin_pwd, "basic", args)
  if(response$status_code != 204) {
    cli_alert_warning("Altering OIDC user failed, please do this manually")
    update_auto = ""
  }
}

wait_for_input <- function(){
  cat("\nPress any key to continue")
  continue <- readLines("stdin", n=1)
}

# log version info of loaded libraries
show_version_info <- function(libs){
  libs_to_print <- cli_ul()
  for (i in 1:length(libs)) {
    lib = libs[i]
    cli_li(sprintf("%s: %s\n", lib, packageVersion(lib)))
  }
  cli_end(libs_to_print)
}

create_dir_if_not_exists <- function(directory){
  if (!dir.exists(paste0(dest, directory))) {
    dir.create(paste0(dest, directory))
  }
}

add_slash_if_not_added <- function(path){
  if (substr(path, nchar(path), nchar(path)) != "/"){
    return(paste0(path, "/"))
  } else {
    return(path)
  }
}

# theres a bit of noise added in DataSHIELD answers, causing calculations to not always be exactly the same, but close
# here we check if they're equal enough
almost_equal <- function(val1, val2) {
  return(all.equal(val1, val2, tolerance= .Machine$double.eps ^ 0.03))
}

# compare values in two lists
compare_list_values <- function(list1, list2) {
  vals_to_print <- cli_ul()
  equal <- TRUE
  for (i in 1:length(list1)) {
    val1 <- list1[i]
    val2 <- list2[i]
    if(almost_equal(val1, val2) == TRUE){
      cli_li(sprintf("%s ~= %s", val1, val2))
    } else {
      equal <- FALSE
      cli_li(sprintf("%s != %s", val1, val2))
    }
  }
  cli_end(vals_to_print)
  if(equal){
    cli_alert_success("Values equal")
  } else {
    cli_alert_danger("Values not equal")
  }
}

print_list <- function(list){
  vals_to_print <- cli_ul()
  for (i in 1:length(list)) {
    val = list[i]
    cli_li(val)
  }
  cli_end(vals_to_print)
}

check_cohort_exists <- function(cohort){
  if(cohort %in% armadillo.list_projects()){
    cli_alert_success(paste0(cohort, " exists"))
  } else {
    exit_test(paste0(cohort, " doesn't exist!"))
  }
}

download_test_files <- function(urls, dest){
  n_files <- length(urls)
  cli_progress_bar("Downloading testfiles", total = n_files)
  for (i in 1:n_files) {
    download_url <- urls[i]
    splitted <- strsplit(download_url, "/")[[1]]
    folder <- splitted[length(splitted) - 1]
    filename <- splitted[length(splitted)]
    cli_alert_info(paste0("Downloading ", filename))
    download.file(download_url, paste0(dest, folder, "/", filename), quiet=TRUE)
    cli_progress_update()
  }
  cli_progress_done()
}

generate_random_project_name <- function(current_projects) {
  random_project <- stri_rand_strings(1, 10, "[a-z0-9]")
  if (!random_project %in% current_projects) {
    return(random_project)
  } else {
    generate_random_project_name(current_projects)
  }
}

generate_random_project_seed <- function(current_project_seeds) {
  random_seed <- round(runif(1, min = 100000000, max=999999999))
  if (!random_seed %in% current_project_seeds) {
    return(random_seed)
  } else {
    generate_random_project_seed(current_project_seeds)
  }
}

generate_project_port <- function(current_project_ports) {
  starting_port <- 6312
  while (starting_port %in% current_project_ports) {
    starting_port = starting_port + 1
  }
  return(starting_port)
}

obtain_existing_profile_information <- function(key, auth_type) {
  responses <- get_from_api_with_header('ds-profiles', key, auth_type)
  response_df <- data.frame(matrix(ncol=5,nrow=0, dimnames=list(NULL, c("name", "container", "port", "seed", "online"))))
  for (response in responses) {
    if("datashield.seed" %in% names(response$options)) {
      datashield_seed <- response$options$datashield.seed
    } else {
      datashield_seed <- NA
    }
    
    response_df[nrow(response_df) + 1,] = c(response$name, response$image, response$port, datashield_seed, response$container$status)
  }
  return(response_df)
}

start_profile <- function(profile_name, key, auth_type) {
  auth_header <- get_auth_header(auth_type, key)
  cli_alert_info(sprintf('Attempting to start profile: %s', profile_name))
  response <- POST(
    sprintf("%sds-profiles/%s/start", armadillo_url, profile_name),
    config = c(httr::add_headers(auth_header))
    )
  if (!response$status_code == 204) {
    exit_test(sprintf("Unable to start profile %s, error code: %s", profile_name, response$status_code))
  } else {
    cli_alert_success(sprintf("Successfully started profile: %s", profile_name))
  }
}

return_list_without_empty <- function(to_empty_list) {
  return(to_empty_list[to_empty_list != ''])
}

create_profile <- function(profile_name, key, auth_type) {
  if (profile_name %in% profile_defaults$name) {
    cli_alert_info(sprintf("Creating profile: %s", profile_name))
    profile_default <- profile_defaults[profile_defaults$name == profile_name,]
    current_profiles <- obtain_existing_profile_information(key, auth_type)
    new_profile_seed <- generate_random_project_seed(current_profiles$seed)
    whitelist <- as.list(stri_split_fixed(paste("dsBase", profile_default$whitelist, sep = ","), ",")[[1]])
    blacklist <- as.list(stri_split_fixed(profile_default$blacklist, ",")[[1]])
    port <- profile_default$port
    if (port == "") {
      port <- generate_project_port(current_profiles$port)
    }
    args <- list(
      name = profile_name, 
      image = profile_default$container, 
      host = "localhost", 
      port = port, 
      packageWhitelist = return_list_without_empty(whitelist),
      functionBlacklist = return_list_without_empty(blacklist),
      options = list(datashield.seed = new_profile_seed)
    )
    response <- put_to_api('ds-profiles', key, auth_type, body_args = args)
    if (response$status_code == 204) {
      cli_alert_success(sprintf("Profile %s successfully created.", profile_name))
      start_profile(profile_name, key, auth_type)
    } else {
      exit_test(sprintf("Unable to create profile: %s , errored %s", profile_name, response$status_code))
    }
  } else {
    exit_test(sprintf("Unable to create profile: %s , unknown profile", profile_name))
  }
}

start_profile_if_not_running <- function(profile_name, key, auth_type) {
  response <- get_from_api_with_header(paste0('ds-profiles/', profile_name), key, auth_type)
  if (!response$container$status == "RUNNING") {
    cli_alert_info(sprintf("Detected profile %s not running", profile_name))
    start_profile(profile_name, key, auth_type)
  }
}

create_profile_if_not_available <- function(profile_name, available_profiles, key, auth_type) {
  if (!profile_name %in% available_profiles) {
    cli_alert_info(sprintf("Unable to locate profile %s, attempting to create.", profile_name))
    create_profile(profile_name, key, auth_type)
  }
  start_profile_if_not_running(profile_name, key, auth_type)
}

create_dsi_builder <- function(server = "armadillo", url, profile, password = "", token = "", table = "", resource = "") {
  cli_alert_info("Creating new datashield login builder")
  builder <- DSI::newDSLoginBuilder()
  if (ADMIN_MODE) {
    cli_alert_info("Appending information as admin")
    builder$append(
      server = server,
      url = url,
      profile = profile,
      table = table,
      driver = "ArmadilloDriver",
      user = "admin",
      password = password,
      resource = resource
    )
  } else {
    cli_alert_info("Appending information using token")
    builder$append(
      server = server,
      url = url,
      profile = profile,
      table = table,
      driver = "ArmadilloDriver",
      token = token,
      resource = resource
    )
  }
  cli_alert_info("Appending information to login builder")
  return(builder$build())
}

create_ds_connection <- function(password = "", token = "", profile = "", url) {
  cli_alert_info("Creating new datashield connection")
  if (ADMIN_MODE) {
    cli_alert_info("Creating connection as admin")
    con <- dsConnect(
      drv = armadillo(),
      name = "armadillo",
      user = "admin",
      password = password,
      url = url,
      profile = profile
    )
  } else {
    cli_alert_info("Creating connection using token")
    con <- dsConnect(
      drv = armadillo(),
      name = "armadillo",
      token = token,
      url = url,
      profile = profile
    )
  }
  return(con)
}

verify_ds_obtained_mean <- function(ds_mean, expected_mean, expected_valid_and_total) {
  if(! round(ds_mean[1], 3) == expected_mean){
    cli_alert_danger(paste0(ds_mean[1], "!=", expected_mean))
    exit_test("EstimatedMean incorrect!")
  } else if(ds_mean[2] != 0) {
    cli_alert_danger(paste0(ds_mean[2], "!=", 0))
    exit_test("Nmissing incorrect!")
  } else if(ds_mean[3] != expected_valid_and_total) {
    cli_alert_danger(paste0(ds_mean[3], "!=", expected_valid_and_total))
    exit_test("Nvalid incorrect!")
  } else if(ds_mean[4] != expected_valid_and_total) {
    cli_alert_danger(paste0(ds_mean[4], "!=", expected_valid_and_total))
    exit_test("Ntotal incorrect!")
  } else {
    cli_alert_success("Mean values correct")
  }
}

# here we start the script chronologically
cli_alert_success("Loaded Armadillo/DataSHIELD libraries:")
show_version_info(c("MolgenisArmadillo", "DSI", "dsBaseClient", "DSMolgenisArmadillo", "resourcer"))

cli_alert_success("Loaded other libraries:")
show_version_info(c("getPass", "arrow", "httr", "jsonlite", "future"))

cat("\nEnter URL of testserver (for default https://armadillo-demo.molgenis.net/, press enter): ")
armadillo_url <- readLines("stdin", n=1)

if(armadillo_url == ""){
  armadillo_url = "https://armadillo-demo.molgenis.net/"
}

armadillo_url <- add_slash_if_not_added(armadillo_url)

if(url.exists(armadillo_url)) {
  cli_alert_success(sprintf("URL [%s] exists", armadillo_url))
  if (!startsWith(armadillo_url, "http")) {
    if (startsWith(armadillo_url, "localhost")) {
        armadillo_url <- paste0("http://", armadillo_url)
    } else {
        armadillo_url <- paste0("https://", armadillo_url)
    }
  }
} else {
  msg <- sprintf("URL [%s] doesn't exist", armadillo_url)
  exit_test(msg)
}

cat("Location of molgenis-service-armadillo on your PC (for default ~/git/, press enter, if not available press x): ")
service_location <- readLines("stdin", n=1)
dest <- ""

cat("Enter password for admin user (basic auth)\n")
admin_pwd<- getPass::getPass()

cat("Enter your OIDC username (email): ")
user <- readLines("stdin", n=1)

if(service_location == "") {
  dest = "~/git/molgenis-service-armadillo/data/shared-lifecycle/"
} else if (service_location == "x") {
  cat("Do you want to download the files? (y/n) ")
  download <- readLines("stdin", n=1)
  if (download == "y") {
    cat("Where do you want to download the files? ")
    dest <- readLines("stdin", n=1)
    if (dir.exists(dest)) {
      cli_alert_info(paste0("Downloading test files into: ", dest))
      dest <- add_slash_if_not_added(dest)
      create_dir_if_not_exists("core")
      create_dir_if_not_exists("outcome")
      test_files_url_template <- "https://github.com/molgenis/molgenis-service-armadillo/raw/master/data/shared-lifecycle/%s/%srep.parquet"
      download_test_files(
        c(
        sprintf(test_files_url_template, "core", "non"),
        sprintf(test_files_url_template, "core", "yearly"),
        sprintf(test_files_url_template, "core", "monthly"),
        sprintf(test_files_url_template, "core", "trimester"),
        sprintf(test_files_url_template, "outcome", "non"),
        sprintf(test_files_url_template, "outcome", "yearly")
        ),
        dest
      )
    } else {
      msg <- sprintf("Release test halted: Directory [%s] doesn't exist", dest)
      exit_test(msg)
    }
  } else {
    msg <- "Release test halted: No test files available"
    exit_test(msg)
  }
} else {
  service_location <- add_slash_if_not_added(service_location)
  dest <- paste0(service_location, "/molgenis-service-armadillo/data/shared-lifecycle/")
  if (!dir.exists(dest)) {
    msg <- sprintf("Release test halted: Directory [%s] doesn't exist", service_location)
    exit_test(msg)
  }
}

cat("Do you have testfile [gse66351_1.rda] downloaded? (y/n) ")
rda_available = readLines("stdin", n=1)
rda_dir = ""
test_resource = "gse66351_1.rda"
if (rda_available == "y"){
  cat(sprintf("Specify path to %s (including filename): ", test_resource))
  rda_dir = readLines("stdin", n=1)
} else {
  cat("Where do you want to download it: ")
  download_dir = readLines("stdin", n=1)
  download_dir <- add_slash_if_not_added(download_dir)
  if(dir.exists(download_dir)){
    cli_alert_info(sprintf("Downloading %s into %s", test_resource, download_dir))
    download.file("https://github.com/isglobal-brge/brge_data_large/raw/master/data/gse66351_1.rda", paste0(download_dir, test_resource))
    rda_dir = paste0(download_dir, test_resource)
  }
}

cli_alert_info("Checking if rda dir exists")
if (rda_dir == "" || !file.exists(rda_dir)) {
  exit_test(sprintf("File [%s] doesn't exist", rda_dir))
}

app_info <- get_from_api("actuator/info")

version <- unlist(app_info$build$version)

cat("\nAvailable profiles: \n")
profiles <- get_from_api("profiles")
print_list(unlist(profiles$available))

cat("Which profile do you want to test on? (press enter to continue using xenon; xenon will be created if unavailable) ")
profile <- readLines("stdin", n=1)
if (profile == "") {
  profile <- "xenon"
}

ADMIN_MODE <- admin_pwd != "" && user == ""
cli_alert_info("Checking if profile is prepared for all tests")
if(ADMIN_MODE){
  api_token <- admin_pwd
  token <- ""
  auth_type <- "basic"
} else {
  api_token <- armadillo.get_token(armadillo_url)
  token <- api_token
  auth_type <- "bearer"
}

create_profile_if_not_available(profile, profiles$available, api_token, auth_type)
profile_info <- get_from_api_with_header(paste0("ds-profiles/", profile), api_token, auth_type)
start_profile_if_not_running("default", api_token, auth_type)

seed <- unlist(profile_info$options$datashield.seed)
whitelist <- unlist(profile_info$packageWhitelist)
if(is.null(seed)){
  cli_alert_warning(sprintf("Seed of profile [%s] is NULL, please set it in UI profile tab and restart the profile", profile))
  wait_for_input()
}
if(!"resourcer" %in% whitelist){
  cli_alert_warning(sprintf("Whitelist of profile [%s] does not contain resourcer, please add it and restart the profile", profile))
  wait_for_input()
}

if(!is.null(seed) && "resourcer" %in% whitelist){
  cli_alert_success(sprintf("Profile [%s] okay for testing", profile))
}

cli_h1("Release test")
cat(sprintf("
                  ,.-----__                       Testing version: %s
            ,:::://///,:::-.                      Test server: %s
           /:''/////// ``:::`;/|/                 OIDC User: %s
          /'   ||||||     :://'`\\                 Admin password set: %s
        .' ,   ||||||     `/(  e \\                Directory for test files: %s
  -===~__-'\\__X_`````\\_____/~`-._ `.              Profile: %s
              ~~        ~~       `~-'             Admin-only mode: %s
", version, armadillo_url, user, admin_pwd != "", dest, profile, ADMIN_MODE))

cli_h2("Table upload")
cli_alert_info(sprintf("Login to %s", armadillo_url))
if(ADMIN_MODE) {
    armadillo.login_basic(armadillo_url, "admin", admin_pwd)
} else {
    armadillo.login(armadillo_url)
}
available_projects <- armadillo.list_projects()
project1 <- generate_random_project_name(available_projects)
available_projects <- c(available_projects, project1)
cli_alert_info(sprintf("Creating project [%s]", project1))
armadillo.create_project(project1)
cli_alert_info(sprintf("Checking if project [%s] exists", project1))
check_cohort_exists(project1)

cli_alert_info("Reading parquet files for core variables")
cli_alert_info("core/nonrep")
nonrep <- arrow::read_parquet(paste0(dest, "core/nonrep.parquet"))
cli_alert_success("core/nonrep read")
cli_alert_info("core/yearlyrep")
yearlyrep <- arrow::read_parquet(paste0(dest, "core/yearlyrep.parquet"))
cli_alert_success("core/yearlyrep read")
cli_alert_info("core/monthlyrep")
monthlyrep <- arrow::read_parquet(paste0(dest, "core/monthlyrep.parquet"))
cli_alert_success("core/monthlyrep read")
cli_alert_info("core/trimesterrep")
trimesterrep <- arrow::read_parquet(paste0(dest, "core/trimesterrep.parquet"))
cli_alert_success("core/trimesterrep read")

cli_alert_info("Uploading core test tables")
armadillo.upload_table(project1, "2_1-core-1_0", nonrep)
armadillo.upload_table(project1, "2_1-core-1_0", yearlyrep)
armadillo.upload_table(project1, "2_1-core-1_0", monthlyrep)
armadillo.upload_table(project1, "2_1-core-1_0", trimesterrep)
cli_alert_success("Uploaded files into core")

rm(nonrep, yearlyrep, monthlyrep, trimesterrep)

cli_alert_info("Reading parquet files for outcome variables")
nonrep <- arrow::read_parquet(paste0(dest, "outcome/nonrep.parquet"))
yearlyrep <- arrow::read_parquet(paste0(dest, "outcome/yearlyrep.parquet"))

cli_alert_info("Uploading outcome test tables")
armadillo.upload_table(project1, "1_1-outcome-1_0", nonrep)
armadillo.upload_table(project1, "1_1-outcome-1_0", yearlyrep)
cli_alert_success("Uploaded files into outcome")

cli_alert_info("Checking if colnames of trimesterrep available")
trimesterrep <- armadillo.load_table(project1, "2_1-core-1_0", "trimesterrep")
cols <- c("row_id","child_id","age_trimester","smk_t","alc_t")
if (identical(colnames(trimesterrep), cols)){
  cli_alert_success("Colnames correct")
} else {
  cli_alert_danger(paste0(colnames(trimesterrep), "!=", cols))
  exit_test("Colnames incorrect")
}

cli_h2("Manual test UI")
cat("\nNow open your testserver in the browser")
cat(sprintf("\n\nVerify [%s] is available", project1))
wait_for_input()
cat("\nClick on the icon next to the name to go to the project explorer")
wait_for_input()
cat("\nVerify the 1_1-outcome-1_0 and 2_1-core-1_0 folders are there")
wait_for_input()
cat("\nVerify core contains nonrep, yearlyrep, monthlyrep and trimesterrep")
wait_for_input()
cat("\nVerify outcome contains nonrep and yearlyrep")
wait_for_input()

cat("\nWere the manual tests successful? (y/n) ")
success <- readLines("stdin", n=1)
if(success != "y"){
  cli_alert_danger("Manual tests failed: problem in UI")
  exit_test("Some values incorrect in UI projects view")
}

cli_h2("Resource upload")
omics_project <- generate_random_project_name(available_projects)
available_projects <- c(available_projects, omics_project)
cli_alert_info(sprintf("Creating project [%s]", omics_project))
armadillo.create_project(omics_project)
rda_file_body <- upload_file(rda_dir)
cli_alert_info(sprintf("Uploading resource file to %s into project [%s]", armadillo_url, omics_project))

post_resource_to_api(omics_project, token, auth_type, rda_file_body, "ewas", "gse66351_1.rda")

cli_alert_info("Creating resource")


rds_url <- armadillo_url
if(armadillo_url == "http://localhost:8080/") {
    rds_url <- "http://host.docker.internal:8080/"
}

resGSE1 <- resourcer::newResource(
  name = "GSE66351_1",
  url = sprintf("%sstorage/projects/%s/objects/ewas%sgse66351_1.rda", rds_url, omics_project,"%2F"),
  format = "ExpressionSet"
)
cli_alert_info("Uploading RDS file")
armadillo.upload_resource(project = omics_project, folder = "ewas", resource = resGSE1, name = "GSE66351_1")

cli_alert_info("\nNow you're going to test as researcher")
if(!ADMIN_MODE){
  cat("\nDo you want to remove admin from OIDC user automatically? (y/n) ")
  update_auto <- readLines("stdin", n=1)
  if(update_auto == "y"){
    set_user(user, admin_pwd, F, project1, omics_project)
  }
  if(update_auto != "y"){
    cat("\nGo to the Users tab")
    cat(sprintf("\nAdd [%s]' and [%s] to the project column for your account", project1, omics_project))
    cat("\nRevoke your admin permisions\n")
    cli_alert_warning("Make sure you either have the basic auth admin password or someone available to give you back your permissions")
    wait_for_input()
  }
}

cli_h2("Using tables as researcher")
cli_alert_info("Creating new builder")
cli_alert_info("Building")
logindata <- create_dsi_builder(
  url = armadillo_url,
  profile = profile,
  password = admin_pwd,
  token = token,
  table = sprintf("%s/2_1-core-1_0/nonrep", project1)
  )

cli_alert_info(sprintf("Login with profile [%s] and table: [%s/2_1-core-1_0/nonrep]", profile, project1))
conns <- datashield.login(logins = logindata, symbol = "core_nonrep", variables = c("coh_country"), assign = TRUE)
cli_alert_info("Assigning table core_nonrep")
datashield.assign.table(conns, "core_nonrep", sprintf("%s/2_1-core-1_0/nonrep", project1))
cli_alert_info("Assigning expression for core_nonrep$coh_country")
datashield.assign.expr(conns, "x", expr=quote(core_nonrep$coh_country))
cli_alert_info("Verifying connecting to profile possible")
con <- create_ds_connection(password = admin_pwd, token = token, url=armadillo_url, profile=profile)
cli_alert_info("Verifying mean function works on core_nonrep$country")
ds_mean <- ds.mean("core_nonrep$coh_country", datasources = conns)$Mean
cli_alert_info("Verifying mean values")
verify_ds_obtained_mean(ds_mean, 431.105, 1000)
cli_alert_info("Verifying can create histogram")
hist <- ds.histogram(x = "core_nonrep$coh_country", datasources = conns)
cli_alert_info("Verifying values in histogram")

breaks <- c(35.31138,116.38319,197.45500,278.52680,359.59861,440.67042,521.74222,602.81403,683.88584,764.95764,846.02945)
counts <- c(106,101,92,103,106,104,105,101,113,69)
density <- c(0.0013074829,0.0012458092,0.0011347965,0.0012704787,0.0013074829,0.0012828134,0.0012951481,0.0012458092,0.0013938261,0.0008510974)
mids <- c(75.84729,156.91909,237.99090,319.06271,400.13451,481.20632,562.27813,643.34993,724.42174,805.49355)
cli_alert_info("Validating histogram breaks")
compare_list_values(hist$breaks, breaks)
cli_alert_info("Validating histogram counts")
compare_list_values(hist$counts, counts)
cli_alert_info("Validating histogram density")
compare_list_values(hist$density, density)
cli_alert_info("Validating histogram mids")
compare_list_values(hist$mids, mids)

if (ADMIN_MODE) {
   cli_alert_warning("Cannot test working with resources as basic authenticated admin")
} else if (!"resourcer" %in% profile_info$packageWhitelist) {
  cli_alert_warning(sprintf("Resourcer not available for profile: %s, skipping testing using resources.", profile))
} else {
    cli_h2("Using resources as regular user")
    login_data <- create_dsi_builder(server = "testserver", url = armadillo_url, token = token, profile = profile, resource = sprintf("%s/ewas/GSE66351_1", omics_project))
    conns <- DSI::datashield.login(logins = login_data, assign = TRUE)
    cli_alert_info("Testing if we see the resource")
    resource_path <- sprintf("%s/ewas/GSE66351_1", omics_project)
    if(datashield.resources(conns = conns)$testserver == resource_path){
      cli_alert_success("Success")
    } else {
      cli_alert_danger("Failure")
    }
    cli_alert_info("Testing if we can assign resource")
    datashield.assign.resource(conns, resource =resource_path, symbol="eSet_0y_EUR")
    cli_alert_info("Getting RObject class of resource")
    resource_class <- ds.class('eSet_0y_EUR', datasources = conns)
    expected <- c("RDataFileResourceClient", "FileResourceClient", "ResourceClient", "R6")
    if (length(setdiff(resource_class$testserver, expected)) == 0) {
      cli_alert_success("Success")
    } else {
      cli_alert_danger("Failure")
    }
    cli_alert_info("Testing if we can assign expression")
    tryCatch({
      datashield.assign.expr(conns, symbol = "methy_0y_EUR",expr = quote(as.resource.object(eSet_0y_EUR)))
    }, error = function(e) {
        cli_alert_danger(datashield.errors())
    })
}

cli_h2("Default profile")
cli_alert_info("Verify if default profile works without specifying profile")
con <- create_ds_connection(password = admin_pwd, token = token, url = armadillo_url)
if (con@name == "armadillo") {
  cli_alert_success("Succesfully connected")
} else {
  cli_alert_danger("Connection failed")
}

cli_alert_info("Verify if default profile works when specifying profile")


con <- create_ds_connection(password = admin_pwd, token = token, url = armadillo_url, profile = "default")
if (con@name == "armadillo") {
  cli_alert_success("Succesfully connected")
} else {
  cli_alert_danger("Connection failed")
}

cli_h2("Removing data as admin")
cat("We're now continueing with the datamanager workflow as admin\n")
if(update_auto == "y"){
  set_user(user, admin_pwd, T, project1, omics_project)
} else{
  cat("Make your account admin again")
  wait_for_input()
}
armadillo.delete_table(project1, "2_1-core-1_0", "nonrep")
armadillo.delete_table(project1, "2_1-core-1_0", "yearlyrep")
armadillo.delete_table(project1, "2_1-core-1_0", "trimesterrep")
armadillo.delete_table(project1, "2_1-core-1_0", "monthlyrep")
armadillo.delete_table(project1, "1_1-outcome-1_0", "nonrep")
armadillo.delete_table(project1, "1_1-outcome-1_0", "yearlyrep")
cat(sprintf("\nVerify in UI all data from [%s] is gone.", project1))
wait_for_input()
armadillo.delete_project(project1)
cat(sprintf("\nVerify in UI project [%s] is gone", project1))
wait_for_input()
armadillo.delete_project(omics_project)
cat(sprintf("\nVerify in UI project [%s] is gone", omics_project))
wait_for_input()

project2 <- generate_random_project_name(available_projects)
available_projects <- c(available_projects, project2)
if(admin_pwd != "") {
  cli_h2("Basic authentication")
  cli_alert_info("Logging in as admin user")
  armadillo.login_basic(armadillo_url, "admin", admin_pwd)
  cli_alert_info(sprintf("Creating project [%s]", project2))
  armadillo.create_project(project2)
  nonrep <- arrow::read_parquet(paste0(dest, "core/nonrep.parquet"))
  cli_alert_info(sprintf("Uploading file to [%s]", project2))
  armadillo.upload_table(project2, "2_1-core-1_0", nonrep)
  rm(nonrep)
  check_cohort_exists(project2)
  table <- sprintf("%s/2_1-core-1_0/nonrep", project2)
  if(table %in% armadillo.list_tables(project2)){
    cli_alert_success(paste0(table, " exists"))
  } else {
    exit_test(paste0(table, " doesn't exist"))
  }
  cli_alert_info(sprintf("Deleting [%s]", project2))
  armadillo.delete_project(project2)
} else {
  cli_alert_warning("Testing basic authentication skipped, admin password not available")
}

cli_h3("Testing Rock profile")
cli_alert_info(sprintf("Loging to %s (please note, this is a double login)", armadillo_url))
if(ADMIN_MODE) {
  armadillo.login_basic(armadillo_url, "admin", token)
} else {
  armadillo.login(armadillo_url)
  token <- armadillo.get_token(armadillo_url)
}
profile <- "rock"
create_profile_if_not_available(profile, profiles$available, token, auth_type)
available_projects <- armadillo.list_projects()
project3 <- generate_random_project_name(available_projects)
available_projects <- c(available_projects, project3)
cli_alert_info(sprintf("Creating project [%s]", project3))
armadillo.create_project(project3)
cli_alert_info(sprintf("Checking if project [%s] exists", project3))
check_cohort_exists(project3)

trimesterrep <- arrow::read_parquet(paste0(dest, "core/trimesterrep.parquet"))
cli_alert_success("core/trimesterrep read")

cli_alert_info("Uploading trimesterrep table")
armadillo.upload_table(project3, "core", trimesterrep)
rm(trimesterrep)
cli_alert_success("Uploaded trimesterrep")

cli_alert_info("Creating new builder")
logindata <- create_dsi_builder(url = armadillo_url, profile = profile, password = admin_pwd, token = token, table = sprintf("%s/core/trimesterrep", project3))

cli_alert_info(sprintf("Login with profile rock and table: [%s/core/trimesterrep]", project3))
conns <- datashield.login(logins = logindata, symbol = "core_trimesterrep", variables = c("smk_t"), assign = TRUE)

datashield.assign.table(conns, "core_trimesterrep", sprintf("%s/core/trimesterrep", project3))

datashield.assign.expr(conns, "x", expr=quote(core_trimesterrep$smk_t))

con <- create_ds_connection(password = admin_pwd, token = token, profile = profile, url = armadillo_url)

if (con@name == "armadillo"){
  cli_alert_success("Succesfully connected")
} else {
  cli_alert_danger("Connection failed")
}

ds_mean <- ds.mean("core_trimesterrep$smk_t", datasources = conns)$Mean

cli_alert_info("Testing Rock profile mean values")
verify_ds_obtained_mean(ds_mean, 61.059, 3000)

armadillo.delete_table(project3, "core", "trimesterrep")
armadillo.delete_project(project3)
cat(sprintf("\nVerify in the UI that project [%s] and all its data is gone.", project3))
wait_for_input()

cli_alert_info("Testing done")
cli_alert_info("Please test rest of UI manually, if impacted this release")
