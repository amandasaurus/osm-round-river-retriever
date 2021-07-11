# RRR - Round River Retreiver

Find, in an OpenStreetMap data file, anything with `natural=water` that should probably have `water=river` tag

## Motivation

There are some river areas in OpenStreetMap which are just tagged `natural=water`, without the correct `water=river` tag. This script adds a `.osm.pbf` to PostgresSQL with [`osm2pgsql`](https://osm2pgsql.org/) and runs some SQL processing to produce a CSV file with points and some metrics which help you find these long skinny `natural=water` objects. This is useful as part of the [OSM River Modernization Project](https://wiki.openstreetmap.org/wiki/WikiProject_Waterways/River_modernization).

## Usage

```bash
./make.sh path/to/FILENAME.osm.pbf [OUTPUT_DIRECTORY]
```

Puts data into `FILENAME.results.csv` (& `.pp0.01.csv` etc) The user you're running this as needs to have password access to postgresql (which is the default). If `OUTPUT_DIRECTORY` is not defined, it uses the current directory.

## Output data

For every OSM object with `natural=water` tag, there's one row in the CSV file(s):

* **`osm_id`**:
* **`water_tag`**: Current value of the `water` tag
* **`latitude`**: of a point on the object
* **`longitude`**:
* **`area_deg2`**: Area of the object in square degrees
* **`area_m2`**: Area of the object in square metres
* **`area_m2`**: Area of the object in square metres
* **`diagonal_len_deg`**: Length (in degrees) of the diagonal of the bounding box
* **`diagonal_len_m`**: Length (in metres) of the diagonal of the bounding box
* **`bbox_area_deg2`**: Area (in square degrees) of the bounding box
* **`bbox_width_deg`**: Width of the bbox in degrees
* **`bbox_height_deg`**: Height of the bbox in degrees
* **`bbox_area_m2`**: Area (in square metres) of the bounding box
* **`mbc_radius_deg`**: radius (in degrees) of the smallest circle which encloses the entire shape.
* **`boundary_len_deg`**: Length of the boundary in degrees
* **`boundary_len_m`**: Length of the boundary in metres
* **`reock_test`**: Value of the [Reock degree of compactness](https://en.wikipedia.org/wiki/Reock_degree_of_compactness)
* **`pp_test`**: Value of the [Polsby–Popper test](https://en.wikipedia.org/wiki/Polsby%E2%80%93Popper_test)

## Changelog

* 2021-07-11: Published on GitHub


## Copyright & Licence

Copyright © 2021, Affero GPL v3+ (see [LICENCE](./LICENCE)). Project is [`osm-round-river-retriever` on GitHub](https://github.com/amandasaurus/osm-round-river-retriever)
