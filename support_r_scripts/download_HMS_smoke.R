#!/usr/bin/env Rscript
# RG Mod 2018-10-16: This seems to not be able to tell this is the salix server
# so it uses old nc files. Modifying code to look at relative path name and if it has
# /srv/ in it, then assume it's salix and not a local machine
# SB Mod 2018-11-17: Thanks for the update Ryan. I tweeked it again because 
# there was an issue running grep from root. 

if(as.character(Sys.info()["nodename"]) == "salix" ){
  machine_name <- 'salix'
}else{
  if(as.character(Sys.info()["nodename"]) == "cvmrit03" ){
    machine_name <- 'cvmrit03'
  } else {
    machine_name <- "local"
  }
}
print(paste("Running code on:", machine_name))


# ------------------------------------------------------------------------------
# Title: Daily HMS smoke plume download 
# Authors: Ryan Gan & Steven Brey 
# Date Created: 6/19/2017
# Created under R Version: 3.3.3
# 
# Updated by David South and Sheena Martenies
# Date updated: 2019-09-11
# R Version 3.6.1
# ------------------------------------------------------------------------------

# This script downloads the latest HMS smoke plume analysis available from 
# the archive at https://www.ospo.noaa.gov/Products/land/hms.html
# If no new analysis is available, i.e. no polygons in the file linked online,
# the latest file is not used, and instead, the older polygons are retained. 

library(tidyverse)
library(readxl)
library(writexl)
library(httr)
library(sf)
library(rvest)
library(rgdal)

if(machine_name == "salix"){
  
  print("-----------------------------------------------")
  print("Code running on salix")
  setwd("/srv/www/rgan/smoke_forecaster/")
  # define path to repository for the server for writing files
  home_path <- paste0("/srv/www/rgan/smoke_forecaster/")
  print(paste("Working directory set to:", home_path))
  print("-----------------------------------------------")
}else{
  if(machine_name == "cvmrit03"){
    
    print("-----------------------------------------------")
    print("Code running on cvmrit03")
    
    # define path to repository for the server for writing files
    home_path <- paste0(getwd(), "/")
    print(paste("Working directory set to:", home_path))
    print("-----------------------------------------------")
  } else {
    
    # Local development taking place. 
    home_path <- paste0(getwd(), "/")  
    print("-----------------------------------------------")
    print("Code running on local machine")
    print("-----------------------------------------------")
  }
}

today <- Sys.Date()
today_char <- as.character(format(today, "%Y%m%d"))

# Get HMS smoke data
urlBase <- "https://satepsanone.nesdis.noaa.gov/pub/FIRE/HMS/GIS/"

#' List of HMS smoke files on the website
hms_files <- read_html(urlBase) %>% 
  html_nodes("a") %>% 
  html_text(trim = T) %>% 
  as.data.frame() %>% 
  rename("hms_files" = ".") %>% 
  mutate(hms_files = as.character(hms_files)) %>% 
  filter(str_detect(hms_files, "smoke"))

#' Temp folder to hold .zip files
if(!dir.exists(paste0(home_path, "data/HMS/Temp"))) dir.create(paste0(home_path, "data/HMS/Temp"))

#' Download the "latest smoke" .zip file
download.file(paste0(urlBase, "latest_smoke.zip"), 
              destfile = paste0(home_path, "data/HMS/Temp/temp.zip"),
              cacheOK = FALSE)

unzip(paste0(home_path, "data/HMS/Temp/temp.zip"), 
      exdir = paste0(home_path, "data/HMS/Temp"))

copy_files <- list.files(paste0(home_path, "data/HMS/Temp/data/oper/newhms/output"))
updated_date <- today
updated_name <- paste0("hms_smoke", today_char, ".prelim")

smoke_sf <- st_read(paste0(home_path, "data/HMS/Temp/data/oper/newhms/output"),
                    updated_name)

#' If copy files is empty or if nrow(today_sf) == 0 it means the "latest_smoke" 
#' file is not yet available
#' We can try the next most recent day or scrape this section all together
check_date <- today - 1

while(length(copy_files) == 0 | nrow(smoke_sf) == 0) {
  do.call(file.remove, list(list.files(paste0(home_path, "data/HMS/Temp/data/oper/newhms/output"), 
                                       full.names = TRUE)))
  
  check_char <- as.character(format(check_date, "%Y%m%d"))
  
  hms_previous <- filter(hms_files, str_detect(hms_files, check_char)) %>% 
    filter(str_detect(hms_files, ".zip")) %>% 
    filter(!str_detect(hms_files, "prelim"))
  
  updated_name <- gsub(".zip", "", hms_previous$hms_files[1])
  
  try_download <- try(
    download.file(paste0(urlBase, hms_previous$hms_files[1]), 
                  destfile = paste0(home_path, "data/HMS/Temp/temp.zip"),
                  cacheOK = FALSE)
  )
  
  if(class(try_download) == "try-error") {
    
    print("No polygon features in the latest file. Not updating for now.")
    
    
  } else {
    download.file(paste0(urlBase, hms_previous$hms_files[1]), 
                  destfile = paste0(home_path, "data/HMS/Temp/temp.zip"),
                  cacheOK = FALSE)
    
    unzip(paste0(home_path, "data/HMS/Temp/temp.zip"), 
          exdir = paste0(home_path, "data/HMS/Temp"))
    
    copy_files <- list.files(paste0(home_path, "data/HMS/Temp/data/oper/newhms/output"))
    smoke_sf <- st_read(paste0(home_path, "data/HMS/Temp/data/oper/newhms/output"),
                        updated_name)
    
    updated_date <- check_date
    check_date <- check_date + 1
  }
} 

updated_date
updated_name

#' Copy the files from the temp directory to the HMS director
for (i in 1:length(copy_files)) {
  
  file.copy(from = paste0(home_path, "data/HMS/Temp/data/oper/newhms/output/", copy_files[i]),
            to = paste0(home_path, "data/HMS/"),
            overwrite = T)
  
  file.remove(paste0(home_path, "data/HMS/Temp/data/oper/newhms/output/", copy_files[i]))
}

#' Read in the shapefiles
#' If there are no features, do not update the "latest_smoke" shapefile
#' We'll need to have some sort of indicator of when the smoke data were updated
#' Maybe don't allow them to be displayed if the download date doesn't match the current date?
#' I'll add an .rda object below that just stores the update date

smoke_path <- paste0(home_path, "data/HMS")

try_error <- try(
  latest_smoke <- st_read(dsn = smoke_path, layer=updated_name, stringsAsFactors = F),
  silent=T
)

#' The same try-error code as Ryan and Steve

if(class(try_error) == "try-error") {
  
  print("No polygon features in the latest file. Not updating for now.")
  
} else {
  
  print("Features in the latest smoke file. Updating the existing.")
  # plot(st_geometry(latest_smoke))
  
  #' Save the updated date as a .rdata 
  #' Maybe we can have a switch that basically only displays the plumes if the data
  #' have been updated (i.e., updated_date == today)
  save(updated_date,  file = paste0(smoke_path, "/plume_update_date.rdata"))
  
  # rewrite the file
  st_write(latest_smoke, 
           dsn = paste0(home_path,"data/HMS"), 
           layer = "latest_smoke_display",
           driver = "ESRI Shapefile",
           delete_layer = T, delete_dsn = T)
  
  # rgdal::writeOGR(obj = latest_smoke,
  #                 dsn = paste0(home_path,"data/HMS"),
  #                 layer = "latest_smoke_display",
  #                 driver = "ESRI Shapefile",
  #                 overwrite_layer = T)
  
}

# TODO: Consider sharing this information with the user on the site.
print(paste("HMS smoke plumes updated on:", updated_date))
print("Script run successfully.")
