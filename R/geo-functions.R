#' Write to geojson easily
#'
#' Provides a user-friendly wrapper for rgdal::writeOGR(). Note,
#' \code{geojson_write} from the geojsonio package
#' provides the same functionality \url{https://github.com/ropensci/geojsonio}.
#'
#' @inheritParams gclip
#' @param filename File name of the output geojson
writeGeoJSON <- function(shp, filename){
  name <- nm <-deparse(substitute(shp))
  rgdal::writeOGR(obj = shp, layer = name, dsn = filename, driver = "GeoJSON")
  newname <- paste0(filename, ".geojson")
  file.rename(filename, newname)
}

#' Simplify geometry of spatial objects with the mapshaper library
#'
#' @section Details:
#'
#' Note: more advance R/mapshaper tools are provided by the rmapshaper
#' package: \url{https://github.com/ateucher/rmapshaper}.
#'
#' Calls the JavaScript command-line GIS application mapshaper
#' (\url{https://github.com/mbloch/mapshaper}) from the system
#' to simplify geographic features, and then tidies up.
#' mapshaper must be installed and available to \code{\link{system}}.
#' \code{mapshape} writes new a file to disk.
#' Thanks to Richard and Adrian Ellison for demonstrating this in R.
#'
#' @param shp A spatial object to be simplified.
#' @param percent A number between 1 and 100 stating how aggressively to simplify
#'  the object (1 is a very aggressive simplification)
#' @param ms_options Text string of options passed to mapshaper such as
#' @param dsn The name of the temporary file to write to (deleted after use)
#' @param silent Logical determining whether the function call is printed to screen
#' \code{no-topology} (a flag) and \code{snap-interval=1} (a key value pair).
#' See the mapshaper documentation for details:
#' \url{https://github.com/mbloch/mapshaper/wiki/Command-Reference}.
#'
#' The percent argument refers to the percentage of removable points to retain.
#' So \code{percent = 1} is a very aggressive simplication, saving a huge amount of
#' hard-disk space.
#' \code{\link[rgeos]{gSimplify}}
#' @export
#' @examples
#' \dontrun{
#' data(routes_fast)
#' shp <- routes_fast[1,]
#' rfs10 <- mapshape(shp)
#' rfs5 <- mapshape(shp, percent = 5)
#' rfs1 <- mapshape(shp, percent = 1)
#' plot(shp)
#' plot(rfs10, add = TRUE, col ="red")
#' plot(rfs5, add = TRUE, col ="blue")
#' plot(rfs1, add = TRUE, col = "grey")
#' # snap the lines to the nearest interval
#' rfs_int <- mapshape(shp, ms_options = "snap-interval=0.001")
#' plot(shp)
#' plot(rfs_int, add = TRUE)
#' }
mapshape <- function(shp, percent = 10, ms_options = "",  dsn = "mapshape", silent = FALSE){
  if(!mapshape_available()) stop("mapshaper not available on this system")
  raster::shapefile(shp, dsn, overwrite = TRUE)
  cmd <- paste0("mapshaper ", ms_options, " ", dsn, ".shp -simplify ", percent, "% -o")
  if(!silent)  print(paste0("Running the following command from the system: ", cmd))
  system(cmd, ignore.stderr = TRUE)
  suppressWarnings(new_shp <- raster::shapefile(paste0(dsn, "-ms.shp")))
  new_shp@data <- shp@data
  proj4string(new_shp) <- proj4string(shp)
  to_remove <- list.files(pattern = dsn)
  file.remove(to_remove)
  new_shp
}

#' Does the computer have mapshaper available?
#'
#' This helper function for \code{\link{mapshape}}
#' determines whether or not the JavaScript library
#' mapshaper is available.
#'
#' @export
#' @examples
#' mapshape_available()
mapshape_available <- function() {
  suppressWarnings(system("mapshaper --version")) != 127
}

#' Crops spatial object x to the bounding box of spatial object (or matrix) b
#'
#' This function is a cross between the spatial subsetting funtions such as
#' sp::over(), rgeos::gIntersects() etc, and the cropping functions of
#' raster::crop() and rgeos::gIntersection(). The output is the subset of
#' spatial object a with an outline described by a square bounding box.
#' The utility of such a function is illustrated in the following question:
#' \url{http://gis.stackexchange.com/questions/46954/clip-spatial-object-to-bounding-box-in-r/}.
#' @param shp The spatial object a to be cropped
#' @param bb the bounding box or spatial object that will be used to crop \code{shp}
#'
#' @export
#' @examples
#' data(cents)
#' bb <- bbox(cents)
#' cb <- rgeos::gBuffer(cents[8, ], width = 0.012, byid = TRUE)
#' plot(cents)
#' plot(cb, add = TRUE)
#' clipped <- gclip(cents, cb)
#' plot(clipped, add = TRUE)
#' clipped$avslope # gclip also returns the data attribute
#' points(clipped)
#' points(cents[cb,], col = "red") # note difference
#' gclip(cents_sf, cb)
gclip <- function(shp, bb) {
  UseMethod("gclip")
}
#' @export
gclip.Spatial <- function(shp, bb) {
  if(class(bb) == "matrix"){
    b_poly <- as(raster::extent(as.vector(t(bb))), "SpatialPolygons")
  }
  else{
    b_poly <- as(raster::extent(bb), "SpatialPolygons")
  }
  clipped <- rgeos::gIntersection(shp, b_poly, byid = TRUE, id = row.names(shp))
  if(grepl("DataFrame", class(shp))){
    if(grepl("SpatialLines", class(shp)) & grepl("SpatialCollections",class(clipped))) {
      geodata <- data.frame(gclip_id = row.names(clipped@lineobj))
    }
    else {
      geodata <- data.frame(gclip_id = row.names(clipped))
    }
    joindata <- cbind(gclip_id = row.names(shp), shp@data)
    geodata <- dplyr::left_join(geodata, joindata)
    row.names(geodata) <- geodata$gclip_id
    #if the data are SpatialPolygonsDataFrame (based on https://stat.ethz.ch/pipermail/r-sig-geo/2008-January/003052.html)
    if(grepl("SpatialPolygons", class(shp))){
      #then rebuild SpatialPolygonsDataFrame selecting relevant rows by row.names (row ID values)
      clipped <- sp::SpatialPolygonsDataFrame(clipped, as(shp[row.names(clipped),], "data.frame"))
    } else if(grepl("SpatialLines", class(shp)) & grepl("SpatialCollections",class(clipped))) {
      clipped <- sp::SpatialLinesDataFrame(clipped@lineobj, geodata)
    } else if(grepl("SpatialLines", class(shp))) {
      clipped <- sp::SpatialLinesDataFrame(clipped, geodata)
    } else { #assumes the data is a SpatialPointsDataFrame
      clipped <- sp::SpatialPointsDataFrame(clipped, geodata)
    }
  }
  clipped@data$gclip_id <- NULL
  clipped
}
#' @export
gclip.sf <- function(shp, bb) {
    shp <- as(shp, "Spatial")
    shp <- gclip.Spatial(shp, as(bb, "Spatial"))
    sf::st_as_sf(shp)
}
#' Scale a bounding box
#'
#' Takes a bounding box as an input and outputs a bounding box of a different size, centred at the same point.
#'
#' @inheritParams gclip
#' @param scale_factor Numeric vector determining how much the bounding box will grow or shrink.
#' Two numbers refer to extending the bounding box in x and y dimensions, respectively.
#' If the value is 1, the output size will be the same as the input.
#' @export
#' @examples
#' bb <- matrix(c(-1.55, 53.80, -1.50, 53.83), nrow = 2)
#' bb1 <- bbox_scale(bb, scale_factor = 1.05)
#' bb2 <- bbox_scale(bb, scale_factor = c(2, 1.05))
#' bb3 <- bbox_scale(bb, 0.1)
#' plot(x = bb2[1,], y = bb2[2,])
#' points(bb1[1,], bb1[2,])
#' points(bb3[1,], bb3[2,])
#' points(bb[1,], bb[2,], col = "red")
bbox_scale <- function(bb, scale_factor){
  if(length(scale_factor == 1)) scale_factor <- rep(scale_factor, 2)
  b <- (bb - rowMeans(bb)) * scale_factor + rowMeans(bb)
  b
}

#' Flexible function to generate bounding boxes
#'
#' Takes a geographic object or bounding box as an input and outputs a bounding box,
#' represented as a bounding box, corner points or rectangular polygon.
#'
#' @inheritParams bbox_scale
#' @param shp Spatial object (from sf or sp packages)
#' @param distance Distance in metres to extend the bounding box by
#' @param output Type of object returned (polygon by default)
#' @aliases bb2poly
#' @seealso bb_scale
#' @export
#' @examples
#' plot(geo_bb(routes_fast, distance = 100), col = "red")
#' plot(geo_bb(routes_fast, scale_factor = 0.8), col = "green", add = TRUE)
#' plot(geo_bb(sp::bbox(routes_fast)), add = TRUE) # works on bb also
#' plot(geo_bb(routes_fast, output = "points"), add = TRUE)
#' # Simple features implementation:
#' bb_sf1 <- geo_bb(routes_fast_sf, scale_factor = c(2, 1.5))
#' bb_sf2 <- geo_bb(routes_fast_sf, c(2, 1.5), distance = 100)
#' plot(bb_sf1)
#' plot(bb_sf2, add = TRUE)
#' plot(routes_fast, add = TRUE)
#' plot(geo_bb(routes_fast_sf, output = "points"), add = TRUE)
#' bb_matrix <- geo_bb(routes_fast, scale_factor = c(2, 1.1), output = "bb")
#' if(require(tmap)) { # as input into tmap plot
#' tm_shape(shp = routes_fast_sf, bbox = bb_matrix) +
#'   tm_lines()
#' }
geo_bb <- function(shp, scale_factor = 1, distance = 0, output = c("polygon", "points", "bb")) {
  UseMethod("geo_bb")
}

#' @export
geo_bb.Spatial <- function(shp, scale_factor = 1, distance = 0, output = c("polygon", "points", "bb")) {
  output <- match.arg(output)
  bb <- geo_bb_matrix(shp)
  bb <- bbox_scale(bb = bb, scale_factor = scale_factor)
  bb <- bb2poly(bb = bb, distance = distance)
  sp::proj4string(bb) <- sp::proj4string(shp)
  if(output == "polygon") {
    return(bb)
  } else if(output == "points") {
    bb_point <- sp::SpatialPoints(raster::geom(bb)[1:4, c(5, 6)])
    sp::proj4string(bb_point) <- sp::proj4string(shp)
    return(bb_point)
  } else if(output == "bb") {
    return(geo_bb_matrix(bb))
  }
}

#' @export
geo_bb.sf <- function(shp, scale_factor = 1, distance = 0, output = c("polygon", "points", "bb")) {
  output <- match.arg(output)
  bb <- geo_bb_matrix(shp)
  bb <- bbox_scale(bb = bb, scale_factor = scale_factor)
  bb_sp <- bb2poly(bb = bb, distance = distance)
  bb <- sf::st_as_sf(bb_sp)
  sf::st_crs(bb) <- sf::st_crs(shp)
  if(output == "polygon") {
    return(bb)
  } else if(output == "points") {
    bb_point <- sp::SpatialPoints(raster::geom(bb_sp)[1:4, c(5, 6)])
    bb_point <- sf::st_as_sf(bb_point)
    sf::st_crs(bb_point) = sf::st_crs(shp)
    return(bb_point)
  } else if(output == "bb") {
    return(geo_bb_matrix(bb))
  }
}

#' @export
geo_bb.bbox <- function(shp, scale_factor = 1, distance = 0, output = c("polygon", "points", "bb")) {
  output <- match.arg(output)
  bb <- matrix(shp, ncol = 2)
  bb <- bbox_scale(bb = bb, scale_factor = scale_factor)
  bb_sp <- bb2poly(bb = bb, distance = distance)
  bb <- sf::st_as_sf(bb_sp)
  sf::st_crs(bb) <- sf::st_crs(shp)
  if(output == "polygon") {
    return(bb)
  } else if(output == "points") {
    bb_point <- sp::SpatialPoints(raster::geom(bb_sp)[1:4, c(5, 6)])
    bb_point <- sf::st_as_sf(bb_point)
    sf::st_crs(bb_point) = sf::st_crs(shp)
    return(bb_point)
  } else if(output == "bb") {
    return(geo_bb_matrix(bb))
  }
}

#' @export
geo_bb.matrix <- function(shp, scale_factor = 1, distance = 0, output = c("polygon", "points", "bb")) {
  output <- match.arg(output)
  if(nrow(shp) != 2) {
    bb <- geo_bb_matrix(shp)
  } else {
    bb <- shp
  }
  bb <- bbox_scale(bb = bb, scale_factor = scale_factor)
  bb <- bb2poly(bb = bb, distance = distance)
  if(output == "polygon") {
    return(bb)
  } else if(output == "points") {
    bb_point <- sp::SpatialPoints(raster::geom(bb)[1:4, c(5, 6)])
    return(bb_point)
  } else if(output == "bb") {
    return(geo_bb_matrix(bb))
  }
}

#' @export
bb2poly <- function(bb, distance = 0){
  if(class(bb) == "matrix"){
    b_poly <- as(raster::extent(as.vector(t(bb))), "SpatialPolygons")
  } else {
    b_poly <- as(raster::extent(bb), "SpatialPolygons")
    proj4string(b_poly) <- proj4string(bb)
  }
  if(distance > 0) {
    b_poly_buff <- geo_buffer(shp = b_poly, width = distance)
    b_poly <- bb2poly(b_poly_buff)
  }
  b_poly
}

#' Create matrix representing the spatial bounds of an object
#'
#' Converts a range of spatial data formats into a matrix representing the bounding box
#'
#' @inheritParams geo_bb
#' @export
#' @examples
#' geo_bb_matrix(routes_fast)
#' geo_bb_matrix(routes_fast_sf)
#' geo_bb_matrix(cents[1, ])
#' geo_bb_matrix(c(-2, 54))
#' geo_bb_matrix(sf::st_coordinates(cents_sf))
geo_bb_matrix <- function(shp) {
  UseMethod("geo_bb_matrix")
}
#' @export
geo_bb_matrix.Spatial <- function(shp) {
  sp::bbox(shp)
}
#' @export
geo_bb_matrix.sf <- function(shp) {
  bb <- sf::st_bbox(shp)
  bb <- matrix(bb, ncol = 2)
  bb
}
#' @export
geo_bb_matrix.numeric <- function(shp) {
  matrix(rep(shp, 2), ncol = 2)
}
#' @export
geo_bb_matrix.matrix <- function(shp) {
  range_x <- range(shp[, 1])
  range_y <- range(shp[, 2])
  matrix(c(range_x, range_y), ncol = 2, byrow = TRUE)
}
