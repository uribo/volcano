##################################
# 日本国内の火山周辺のDEMデータから、立体的な可視化を行う
##################################
library(dplyr)
library(sf)
library(raster)
library(stars)
library(rayshader)
library(geoviz)
library(conflicted)
conflict_prefer("filter", "dplyr")
conflict_prefer("select", "dplyr")
conflict_prefer("extract", "raster")

buffer_contains_10km_meshes <- function(sf_buffer, prefcode) {
  jpmesh::administration_mesh(code = jpndistrict::code_reform(prefcode),
                              to_mesh_size = 10) %>%
    sf::st_crop(sf_buffer) %>%
    dplyr::pull(meshcode) %>%
    purrr::map_chr(
      ~ stringr::str_c(stringr::str_sub(.x, 1, 4),
                       "-",
                       stringr::str_sub(.x, 5, 6)))
}
# 複数になる場合...
alos_path <- function(df_coords) {
  bb <-
    sf::st_bbox(df_coords) %>%
    unname()
  bb_x <- trunc(bb[1], digits = 0) + seq(0, trunc(bb[3], digits = 0) - trunc(bb[1], digits = 0))
  bb_y <- trunc(bb[2], digits = 0) + seq(0, trunc(bb[4], digits = 0) - trunc(bb[2], digits = 0))
  n1 <- dplyr::case_when(
    dplyr::between(bb_y, 20, 24) ~ 20,
    dplyr::between(bb_y, 25, 29) ~ 25,
    dplyr::between(bb_y, 30, 34) ~ 30,
    dplyr::between(bb_y, 35, 39) ~ 35,
    dplyr::between(bb_y, 40, 44) ~ 40,
    dplyr::between(bb_y, 45, 50) ~ 45)
  e1 <- dplyr::case_when(
    dplyr::between(bb_x, 120, 124) ~ 120,
    dplyr::between(bb_x, 125, 129) ~ 125,
    dplyr::between(bb_x, 130, 134) ~ 130,
    dplyr::between(bb_x, 135, 139) ~ 135,
    dplyr::between(bb_x, 140, 144) ~ 140,
    dplyr::between(bb_x, 145, 149) ~ 145,
    dplyr::between(bb_x, 150, 154) ~ 150,
    dplyr::between(bb_x, 155, 159) ~ 155)
  tidyr::crossing(e1, n1, bb_x, bb_y) %>%
    dplyr::mutate_at(vars(bb_x, bb_y), 
                     list(~ sprintf("%03d", .))) %>%
    glue::glue_data("N{sprintf('%03d', n1)}E{e1}_N{sprintf('%03d', n1+5L)}E{e1+5L}/N{bb_y}E{bb_x}_AVE_DSM.tif")
}

alos_circular <- function(data) {
  r_list <-
    fs::dir_ls("~/Documents/resources/JAXA/全球数値地表モデル/",
               type = "file",
               recurse = TRUE,
               regexp = alos_path(data) %>%
                 stringr::str_c(collapse = "|")) %>%
    purrr::map(stars::read_stars)
  r_list %>%
    purrr::map(
      ~ as(.x, "Raster")
    ) %>%
    purrr::reduce(merge) %>%
    stars::st_as_stars() %>%
    sf::st_crop(data) %>%
    as("Raster")
}

make_rayshader_data <- function(m, zscale = 1, min_area = -100) {
  elmat <-
    m %>%
    extract(y = extent(m),
            buffer = 10) %>%
    matrix(nrow = ncol(m),
           ncol = nrow(m))
  ambmat <-
    ambient_shade(elmat, zscale = zscale)
  raymat <-
    ray_shade(elmat, lambert = FALSE)
  watmat <-
    detect_water(elmat, zscale = zscale, min_area = min_area)
  p_data <-
    elmat %>%
    sphere_shade(zscale = zscale, texture = "desert") %>%
    add_water(watmat,
              color = "desert") %>%
    add_shadow(ambmat)
  scene <-
    elmat %>%
    sphere_shade(sunangle = 270, texture = "desert") %>%
    add_overlay(slippy_overlay(m,
                               image_source = "stamen",
                               image_type = "watercolor",
                               png_opacity = 0.5) %>%
                  elevation_transparency(m,
                                         pct_alt_high = 0.5,
                                         alpha_max = 0.9))
  list(data = p_data,
       elmat = elmat,
       scene = scene,
       m = m)
}

# 火山 ALOS ----------------------------------------------------------------------
if (file.exists(here::here("data/volcano_list39.rds")) == FALSE) {
  library(rvest)
  source("https://gist.githubusercontent.com/uribo/80a94a911b5cc81e5182809f2f8da7a0/raw/12b3269f1fa9cccfdfdda47ea17cd4d1526e353a/jgd2011.R")
  x <-
    read_html("https://www.gsi.go.jp/bousaichiri/volcano-maps-vbm.html")
  df_volcano_list <-
    bind_rows(
      tibble::tibble(
        name = x %>%
          html_nodes(css = '#layout > tr > td.w100p > div > div > div > div > div > table') %>%
          html_nodes(css = "tr > td > a") %>%
          html_text() %>%
          stringr::str_subset("データ", negate = TRUE)
      ) %>%
        bind_cols(x %>%
                    html_nodes(css = '#layout > tr > td.w100p > div > div > div > div > div > table') %>%
                    html_nodes(css = "tr > td > a") %>%
                    html_attr("href") %>%
                    stringr::str_subset("^https://maps.gsi.go.jp/") %>%
                    stringr::str_remove(".+#15/") %>%
                    stringr::str_remove("/&base=(std|blank).+") %>%
                    stringr::str_split("/") %>%
                    purrr::reduce(rbind) %>%
                    as.data.frame() %>%
                    as_tibble() %>%
                    mutate_all(list(~ as.double(as.character(.)))) %>%
                    purrr::set_names(c("latitude", "longitude"))),
      tibble::tibble(
        name = x %>%
          html_nodes(css = '#layout > tr > td.w100p > div > div > div > div > div > table') %>%
          html_nodes(css = "tr > td > strong > a") %>%
          html_text()) %>%
        bind_cols(x %>%
                    html_nodes(css = '#layout > tr > td.w100p > div > div > div > div > div > table') %>%
                    html_nodes(css = "tr > td > strong > a") %>%
                    html_attr("href") %>%
                    stringr::str_subset("^https://maps.gsi.go.jp/") %>%
                    stringr::str_remove(".+#15/") %>%
                    stringr::str_remove("/&base=(std|blank).+") %>%
                    stringr::str_split("/") %>%
                    purrr::reduce(rbind) %>%
                    as.data.frame() %>%
                    as_tibble() %>%
                    mutate_all(list(~ as.double(as.character(.)))) %>%
                    purrr::set_names(c("latitude", "longitude")))) %>%
    arrange(desc(latitude), desc(longitude)) %>%
    st_as_sf(coords = c("longitude", "latitude"), crs = 4326)
  # 西之島 は除く
  df_volcano_list <-
    df_volcano_list %>%
    slice(-40L) %>%
    tibble::rowid_to_column()
  df_volcano_list <-
    df_volcano_list %>%
    mutate(srid = df_volcano_list %>%
             group_by(rowid) %>%
             group_map(~ st_join(.x, sf_jgd2011_bbox) %>%
                         pull(srid) %>%
                         purrr::pluck(1) %>%
                         as.character() %>%
                         as.numeric()) %>%
             unlist()) %>%
    dplyr::select(rowid, srid, name, geometry)
  df_volcano_list <-
    df_volcano_list %>%
    group_by(rowid) %>%
    group_map(
      ~ .x %>%
        st_transform(crs = .x$srid) %>%
        # 半径10kmバッファ
        st_buffer(units::set_units(10, km)) %>%
        st_transform(crs = 4326)
    ) %>%
    purrr::reduce(rbind) %>%
    assertr::verify(dim(.) == c(39, 3))
  df_volcano_list %>%
    readr::write_rds(here::here("data/volcano_list39.rds"), compress = "xz")
  d_raster <-
    seq_len(nrow(df_volcano_list)) %>%
    purrr::map(
      ~ alos_circular(df_volcano_list %>% slice(.x)))
  d_raster %>%
    readr::write_rds(here::here("data/volcano_raster.rds"), compress = "xz")
  df_volcano_elv <-
    seq_len(nrow(df_volcano_list)) %>%
    purrr::map_df(
      ~ alos_circular(df_volcano_list %>% slice(.x)) %>%
        as.data.frame(xy = TRUE) %>%
        tibble::as_tibble() %>%
        dplyr::rename("Elevation" = layer),
      .id = "id") %>%
    mutate(id = forcats::fct_inorder(id))
  df_volcano_elv %>%
    readr::write_rds(here::here("data/volcano_elevation.rds"), compress = "xz")
} else {
  df_volcano_list <-
    readr::read_rds(here::here("data/volcano_list39.rds"))
  d_raster <-
    readr::read_rds(here::here("data/volcano_raster.rds"))
  df_volcano_elv <-
    readr::read_rds(here::here("data/volcano_elevation.rds"))
}

if (file.exists(here::here("data/volcano_rayshader.rds")) == FALSE) {
  volcano_rayshader_list <- 
    seq(nrow(df_volcano_list)) %>%
    purrr::map(
      function(.x) {
        m <- alos_circular(df_volcano_list %>% slice(.x))
        make_rayshader_data(m,
                            zscale = raster_zscale(m) / 2,
                            min_area = 0)
      }) %>% 
    purrr::set_names(df_volcano_list$name)
  volcano_rayshader_list %>% 
    readr::write_rds(here::here("data/volcano_rayshader.rds"), compress = "xz")
} else {
  volcano_rayshader_list <-
    readr::read_rds(here::here("data/volcano_rayshader.rds"))
}

# rayshader ---------------------------------------------------------------
if (length(fs::dir_ls(here::here("figures"), regexp = "rayshader_mt.+.png")) != 39) {
  seq(nrow(df_volcano_list)) %>%
    purrr::walk(
      function(.x) {
        d <- volcano_rayshader_list[[.x]]
        d$scene %>%
          plot_3d(d$elmat,
                  zscale = 10,
                  fov = 0,
                  theta = 0,
                  zoom = 0.56,# 0.7
                  phi = 45,
                  solid = FALSE,
                  shadow = TRUE,
                  soliddepth = -10,
                  windowsize = c(800, 620))
        rgl::rgl.texts(x = 430,
                  y = 600,
                  z = 700,
                  text = "DEM: ALOS World 3D - 30m (\u00a9JAXA)",
                  adj = -0.3,
                  pos = NULL,
                  offset = 1.0,
                  color = "black")
        rgl::rgl.texts(x = 430,
                  y = 660,
                  z = 700,
                  text = "MapTile: Stamen Design (CC BY 3.0 )",
                  adj = -0.3,
                  pos = NULL,
                  offset = 1.0,
                  color = "black")
        render_snapshot(glue::glue("figures/rayshader_mt{sprintf('%02d', .x)}_{df_volcano_list %>% slice(.x) %>% pull(name)}.png"), clear = TRUE)
      })
}
