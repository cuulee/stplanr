#' Select a custom projected CRS for the area of interest
#'
#' This function takes a spatial object with a geographic (WGS84)
#' CRS and returns a custom projected CRS focussed on the centroid of the object.
#' This function is especially useful for using units of metres in all directions
#' for data collected anywhere in the world.
#'
#' The function is based on this stackexchange answer:
#' \url{http://gis.stackexchange.com/questions/121489}
#'
#' @param shp A spatial object with a geographic (WGS84) coordinate system
#' @export
#' @examples
#' bbox(routes_fast)
#' proj4string(routes_fast) <- CRS("+init=epsg:4326")
#' new_crs <- crs_select_aeq(routes_fast)
#' rf_projected <- spTransform(routes_fast, new_crs)
#' bbox(rf_projected)
#' line_length <- rgeos::gLength(rf_projected, byid = TRUE)
#' plot(line_length, rf_projected$length)
#' shp = sf::st_sf(sf::st_sfc(sf::st_point(c(1, 0))))
#' geo_select_aeq(shp)
#' @export
geo_select_aeq <- function(shp) {
  UseMethod("geo_select_aeq")
}
#' @export
geo_select_aeq.Spatial <- function(shp){
  crs_select_aeq(shp)
}
#' @export
geo_select_aeq.sf <- function(shp){
  cent <- sf::st_geometry(shp)
  coords <- sf::st_coordinates(shp)
  coords_mat <- matrix(coords[,1:2], ncol = 2)
  midpoint <- apply(coords_mat, 2, mean)
  aeqd <- sprintf("+proj=aeqd +lat_0=%s +lon_0=%s +x_0=0 +y_0=0",
                  midpoint[1], midpoint[1])
  sf::st_crs(aeqd)
}

#' Perform GIS functions on a temporary, projected version of a spatial object
#'
#' This function performs operations on projected data.
#'
#' @param shp A spatial object with a geographic (WGS84) coordinate system
#' @param fun A function to perform on the projected object (e.g. the the rgeos or sf packages)
#' @param crs An optional coordinate reference system (if not provided it is set
#' automatically by \code{\link{crs_select_aeq}})
#' @param silent A binary value for printing the CRS details (default: TRUE)
#' @param ... Arguments to pass to \code{fun}, e.g. \code{byid = TRUE} if the function is \code{\link[rgeos]{gLength}}))
#' @aliases gprojected
#' @export
#' @examples
#' library(sf)
#' shp = routes_fast_sf[2:4,]
#' plot(geo_projected(shp, st_buffer, dist = 100)$geometry)
#' shp = sf::as_Spatial(shp$geometry)
#' geo_projected(shp, fun = rgeos::gBuffer, width = 100, byid = TRUE)
#' rlength = geo_projected(routes_fast, fun = rgeos::gLength, byid = TRUE)
#' plot(routes_fast$length, rlength)
geo_projected <- function(shp, fun, crs, silent, ...) {
  UseMethod(generic = "geo_projected")
}
#' @export
geo_projected.sf <- function(shp, fun, crs = geo_select_aeq(shp), silent = TRUE, ...){
  # assume it's not projected  (i.e. lat/lon) if there is no CRS
  if(is.na(sf::st_crs(shp))) {
    sf::st_crs(shp) <- 4326
  }
  crs_orig <- sf::st_crs(shp)
  shp_projected <- sf::st_transform(shp, crs)
  if(!silent) {
    message(paste0("Running function on a temporary projection: ", crs$proj4string))
  }
  res <- fun(shp_projected, ...)
  if(grepl("sf", x = class(res)[1]))
    res <- sf::st_transform(res, crs_orig)
  res
}
#' @export
geo_projected.Spatial <- function(shp, fun, crs = geo_select_aeq(shp), silent = TRUE, ...){
  # assume it's not projected  (i.e. lat/lon) if there is no CRS
  if(!is.na(is.projected(shp))){
    if(is.projected(shp)){
      res <- fun(shp, ...)
    } else {
      shp_projected <- reproject(shp, crs = crs)
      if(!silent) {
        message(paste0("Running function on a temporary projection: ", crs))
      }
      res <- fun(shp_projected, ...)
      if(is(res, "Spatial"))
        res <- spTransform(res, CRS("+init=epsg:4326"))
    }
  } else {
    shp_projected <- reproject(shp, crs = crs)
    if(!silent) {
      message(paste0("Running function on a temporary projection: ", crs$proj4string))
    }
    res <- fun(shp_projected, ...)
    if(is(res, "Spatial"))
      res <- spTransform(res, CRS("+init=epsg:4326"))
  }
  res
}
#' @export
gprojected <- geo_projected.Spatial
#' Perform a buffer operation on a temporary projected CRS
#'
#' This function solves the problem that buffers will not be circular when used on
#' non-projected data.
#' @param shp A spatial object with a geographic CRS (e.g. WGS84)
#' around which a buffer should be drawn
#' @param dist The distance (in metres) of the buffer (when buffering simple features)
#' @param width The distance (in metres) of the buffer (when buffering sp objects)
#' @param ... Arguments passed to the buffer (see \code{?rgeos::gBuffer} or \code{?sf::st_buffer} for details)
#' @seealso buff_geo
#' @examples
#' buff_sp = geo_buffer(routes_fast, width = 100)
#' class(buff_sp)
#' plot(buff_sp, col = "red")
#' routes_fast_sf = sf::st_as_sf(routes_fast)
#' buff_sf = geo_buffer(routes_fast_sf, dist = 50)
#' class(buff_sf)
#' plot(buff_sf$geometry, add = TRUE)
#' @export
geo_buffer <- function(shp, dist = NULL, width = NULL, ...) {
  UseMethod("geo_buffer")
}

#' @export
geo_buffer.sf <- function(shp, ...) {
  geo_projected(shp, sf::st_buffer, ...)
}

#' @export
geo_buffer.Spatial <- function(shp, ...) {
  geo_projected.Spatial(shp = shp, fun = rgeos::gBuffer, ...)
}
