#!/bin/bash

# Round River Retriever - Generate a CSV file

# Changes

# May 13 2021
#  * Including things with a water tag
#
# May 13 2021
#  * Added bbox & diagonal values to CSV


set -o errexit -o nounset

echo "
     _____
  __|__   |__  _____  __   _  ____   _  _____
 |     |     |/     \|  | | ||    \ | ||     \ 
 |     \     ||     ||  |_| ||     \| ||      \ 
 |__|\__\  __|\_____/|______||__/\____||______/ 
    |_____|
     _____
  __|__   |__  ____  __    _ ______  _____
 |     |     ||    |\  \  //|   ___||     |
 |     \     ||    | \  \// |   ___||     \ 
 |__|\__\  __||____|  \__/  |______||__|\__\ 
    |_____|
     _____
  __|__   |__  ______    __    _____   ____  ______  __    _ ______  _____
 |     |     ||   ___| _|  |_ |     | |    ||   ___|\  \  //|   ___||     | 
 |     \     ||   ___||_    _||     \ |    ||   ___| \  \// |   ___||     \ 
 |__|\__\  __||______|  |__|  |__|\__\|____||______|  \__/  |______||__|\__\ 
    |_____|

"

if [ "${1:- }" = "-h" ] ; then

	cat <<-HELP
	$(basename "$0") path/to/FILENAME.osm.pbf [OUTPUT_DIRECTORY]
	Puts data into FILENAME.results.csv (& .pp0.01.csv etc)
	The user you're running this as needs to have password access to postgresql
	(which is the default)
	If OUTPUT_DIRECTORY is not defined, it uses the current directory.
	HELP
	exit 0
fi


# Input filename
FILENAME=$(realpath "${1:?Arg1 must be filename}")

# Where to store output
OUTPUTDIR=$(realpath "${2:-.}")

# for planet-latest.osm.obf we calculate the "planet" part
PREFIX=$(basename "$FILENAME")
PREFIX=${PREFIX%%.osm.pbf}
PREFIX=${PREFIX%%-latest}
PREFIX=${PREFIX//-/_}

cd "$OUTPUTDIR" || exit

if [ ! -s "${FILENAME}" ] ; then
	echo "$FILENAME doesn't exist" >&2
	exit 1
fi

# Do we need to generate the OSM PBF file for the data we want?
if [ "$FILENAME" -nt "${PREFIX}.natural-water.osm.pbf" ] ; then
	echo "Computing OSM PBF file for everything with natural=water"

	# Get the ids of everything with a natural=water

	# A little temporary text file to store the results
	TMPFILE_NATURAL_WATER=$(mktemp -p . "tmp.${PREFIX}.natural-water.XXXXXX.osm.pbf")

	# osmium reads an OSM PBF file, and with tags-filter spits out only some objects.
	# natural=water = only output things with the natural tag being set to water
	osmium tags-filter --overwrite "$FILENAME" -o "$TMPFILE_NATURAL_WATER" natural=water
	mv "$TMPFILE_NATURAL_WATER" "${PREFIX}.natural-water.osm.pbf"
fi

# use .planet.imported as a temp file to say "yep, we have added this to postgresql"
if [ "${PREFIX}.natural-water.osm.pbf" -nt ".${PREFIX}.imported" ] ; then

	echo "Importing into PostgreSQL"

	# Load into postgresql. -C is for node cache. IME 4000 is fine for a planet file.
	osm2pgsql -C 4000 -p "rivers_${PREFIX}" -l --hstore-all "${PREFIX}.natural-water.osm.pbf"

	# We don't need these tables, so delete them to save space
	for T in point line roads ; do
		psql -c "DROP TABLE rivers_${PREFIX}_${T};"
	done

	# Record that we've done it
	touch ".${PREFIX}.imported"

fi


# use .planet.imported as a temp file to say "yep, we have added this to postgresql"
if [ ".${PREFIX}.imported" -nt ".${PREFIX}.data-calculated" ] || [ "$0" -nt ".${PREFIX}.data-calculated" ] ; then

	echo "Performing the data calculation into water_shapes_${PREFIX}..."
	psql -c "DROP TABLE IF EXISTS water_shapes_${PREFIX};"
	psql -c "
	CREATE TABLE IF NOT EXISTS water_shapes_${PREFIX} AS (
	-- Multi stage processing with postgres!
	WITH
		-- Step 1, just get the data
		waters AS (
			select
				osm_id,

				-- this is the actual geometry
				way,

				tags->'water' as water_tag,

				-- A point which is on the polygon. The geometric centroid
				-- might not be on the polygon. this ensures we get a point
				-- geometry to use as a label
				st_pointonsurface(way) as centroid,

				-- geography type in PostGIS is the special 'everything on a
				-- globe and distances in meters'. It makes other things easier
				-- later.
				way::geography as geog
			FROM rivers_${PREFIX}_polygon

			-- postgresql hstore type. Everything with a natural=water tag and no water tag.
			-- In theory it should not be needed, but just in case
			WHERE tags->'natural' = 'water'
			),

		-- Step 2
		waters_with_stats AS (
			select
				-- Same data as above (ie all columns)
				*,
				
				-- The area of the polygon in square degrees. This is not a
				-- useful measurement in the real world
				st_area(way) as area_deg2,
				
				-- Bounding Box.
				st_envelope(way) as bbox_geometry,
				-- Bounding Box, but convert to GEOGRAPHY
				st_envelope(way)::geography as bbox_geography,

				st_boundingdiagonal(way) as diagonal,


				-- ExteriorRing = the boundary
				-- Get the length of that (again, in degrees)
				st_length(st_exteriorring(way)) as boundary_len_deg,


				-- magic here
				-- This is a postgis function which gets the radius of the smallest circle which encloses the entire shape.
				(ST_MinimumBoundingRadius(way)).radius as mbc_radius_deg

				-- This would be interesting, but my version of PostGIS is too old.
				--(ST_MaximumInscribedCircle(way::geometry)).radius as minbc_radius_deg
			from waters
			)

		-- This select query outputs the columns for the final table for the CSV
		select
			case when osm_id < 0 then 'r' else 'w' end || abs(osm_id) as osm_id,

			water_tag,

			-- lat & lon. yes X = lat & y = lon, so it's the other way around
			ST_Y(centroid) as latitude,
			st_X(centroid) as longitude,
			area_deg2,
			-- the geography type here now gives us the area in square meters
			st_area(geog) as area_m2,

			st_length(diagonal) as diagonal_len_deg,
			st_length(diagonal::geography) as diagonal_len_m,


			-- The area of the bbox polygon in square degrees.
			st_area(bbox_geometry) as bbox_area_deg2,
			-- BBOX width & height
			(st_xmax(bbox_geometry) - st_xmin(bbox_geometry)) as bbox_width_deg,
			(st_ymax(bbox_geometry) - st_ymin(bbox_geometry)) as bbox_height_deg,

			-- The area of the bbox polygon in meters by casting to geography
			st_area(bbox_geography) as bbox_area_m2,

			mbc_radius_deg,
			--minbc_radius_deg,

			boundary_len_deg,

			-- length of the boundary in metres
			st_length(st_exteriorring(way)::geography) as boundary_len_m,

			-- area/radius of this circle. This is a Roeck (or Reocke test)
			area_deg2/mbc_radius_deg as roeck_test,

			-- https://en.wikipedia.org/wiki/Polsby%E2%80%93Popper_test
			4*pi()*area_deg2/(boundary_len_deg*boundary_len_deg) as pp_test

		from waters_with_stats
	);"

	echo "Done. Data is in the PostgreSQL table water_shapes_${PREFIX}..."

	touch ".${PREFIX}.data-calculated"
fi


if [ ".${PREFIX}.data-calculated" -nt "${PREFIX}.results.csv" ] ; then
	echo "Calculating results in ${PREFIX}.results.csv"

	TMPFILE=$(mktemp -p . "tmp.${PREFIX}.results.XXXXXX.csv")
	# PostgreSQL has a "COPY" command which outputs to CSV. So save this table as CSV
	psql -c "COPY water_shapes_${PREFIX} TO STDOUT CSV HEADER" > "${TMPFILE}"
	mv "$TMPFILE" "${PREFIX}.results.csv"

	# make a ZIP file if needed
	if [ "${PREFIX}.results.csv" -nt "${PREFIX}.results.zip" ] ; then
		rm -f "${PREFIX}.results.zip"
		zip "${PREFIX}.results.zip" "${PREFIX}.results.csv"
	fi
fi

# Dump subsets of the data, so it's easier to load
for LIMIT in "0.01" "0.05" ; do
	if [ ".${PREFIX}.imported" -nt "${PREFIX}.results.pp${LIMIT}.csv" ] ; then
		echo "Calculating results in ${PREFIX}.results.pp${LIMIT}.csv"
		TMPFILE=$(mktemp -p . "tmp.${PREFIX}.results.XXXXXX.csv")
		# COPY can also take a SQL column, which we do here. Only select the osm objects with a pp below this
		psql -c "COPY (select * from water_shapes_${PREFIX} where pp_test < ${LIMIT} ) TO STDOUT CSV HEADER" > "${TMPFILE}"
		mv "$TMPFILE" "${PREFIX}.results.pp${LIMIT}.csv"
	fi

	if [ "${PREFIX}.results.pp${LIMIT}.csv" -nt "${PREFIX}.results.pp${LIMIT}.zip" ] ; then
		# make a zip
		rm -f "${PREFIX}.results.pp${LIMIT}.zip"
		zip "${PREFIX}.results.pp${LIMIT}.zip" "${PREFIX}.results.pp${LIMIT}.csv"
	fi
done

echo "Everything done. Results in ${PREFIX}.results.csv etc"
