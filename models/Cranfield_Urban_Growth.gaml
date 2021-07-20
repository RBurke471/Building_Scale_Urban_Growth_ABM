/**
 *  Cranfield_Urban_Growth
 *  Author: Richard Burke
 *  Description: 
 */

model Cranfield_Urban_Growth

global {
	//Load in shapefiles for model.
    file road_shapefile <- file("../includes/Roads_Poly.shp");
	file road_line_shapefile <- file("../includes/Roads.shp");
	file building_shapefile <- file("../includes/Build_test.shp");
	file building_block_shapefile <- file ("../includes/Parcels_Only.shp");
	file river_shapefile <- file("../includes/Rivers");
	file bounds_shapefile <- file("../includes/Cranfield_CP.shp");
	file river_line_shapefile <- file("../includes/SP_SurfaceWater_Line_Study_Area.shp");
	file procedural_road_shapefile <- file("../includes/Procedural_Roads.shp");
	file CBD_shapefile <- file("../includes/CBD.shp");
	
	string twenties1 <- "twenties1";
	string twenties2 <- "twenties2";
	string thirties1 <- "thirties1";
	string thirties2 <- "thirties2";
	string forties1 <- "forties1";
	string forties2 <- "forties2";
	
	
	map<string, rgb> building_color <- map([twenties1::rgb("green"), twenties2::rgb("yellow"), thirties1 ::rgb("darkviolet"), thirties2::rgb("red"), forties1 ::rgb("blue"), forties2 ::rgb("brown")]);
	
	
	graph road_network;
	geometry shape <- envelope(bounds_shapefile); //Create bounding box from geometry.
	float step <- 1 #year;  //Timestep for each simulation cycle.
	int cycle;
	float time;
	bool batch_mode <- false;
	bool save_dist <- false;
	
	float w1 <- 0.25; // Weight value of CBD distance
	float w2 <- 0.25; //Weight value for road distance criteria
	float w3 <- 0.25; //Weight value for slope criteria
	float w4 <- 0.25; //Weight value for river distance criteria
	
	
	// The lower these values the faster the simulation runs, e.g. could consider 6 month timesteps.
	int n <- 362; // Number of building blocks to choose to construct buildings in each cycle.
	int nb_build <- 1; //Number of buildings to construct in each building block in each cycle.
	float distance_building <- 1.0;
	
	
	float crit_roads_max;
	float crit_roads_min;
	float crit_rivers_max;
	float crit_rivers_min;
	float crit_CBD_max;
	float crit_CBD_min;
	float crit_slope_max;
	float crit_slope_min;
	
	string dist_path <- "../includes/vector_distances.csv";
	matrix dist;
	
	int year <- 2021; //Start year of simulation.
	date starting_date <- date([year]);
		
	init {
		create road from: road_shapefile;
		create CBD from: CBD_shapefile;
		create procedural_road from: procedural_road_shapefile;
		create road_line from: road_line_shapefile;
		road_network <- as_edge_graph(road_line);
		create river from: river_shapefile;
		create river_line from: river_line_shapefile;
		create building from: building_shapefile {
			color <- building_color[type];
			}
		
		create building_block from: building_block_shapefile;
		create Cranfield from: bounds_shapefile;
		if (not save_dist) {
			dist <- matrix(csv_file(dist_path, ";"));
		}
		do building_block_creation;
		
	}
	
	
	
	// Execute reflex when criteria weights are not equal to 0.
	reflex global_dynamic when: w1 != 0 or w2 != 0 or w3 != 0 or w4 != 0 {
		//Ask each building block to compute criteria and it constructability.
		list<building_block> bb_to_builds <- building_block where (each.possible_construction); //List building blocks which are possible to have construction on.
		ask bb_to_builds{
			do compute_criteria;
		}
		crit_roads_max <- building_block max_of (each.crit_roads);
		crit_roads_min <- building_block min_of (each.crit_roads);
		crit_rivers_max <- building_block max_of (each.crit_rivers);
		crit_rivers_min <- building_block min_of (each.crit_rivers);
		crit_CBD_max <- building_block max_of (each.crit_CBD);
		crit_CBD_min <- building_block min_of (each.crit_CBD);
		crit_slope_max <- building_block max_of (each.crit_slope);
		crit_slope_min <- building_block min_of (each.crit_slope);
					
		ask bb_to_builds{
			do compute_land_value;
		}
		// Ask the n building blocks with higher constructability to construct buildings.
		list<building_block> sorted_bb <- bb_to_builds sort_by (- each.constructability); //Create list of building_block sorted by constructability.
		// Loop number of times, whichever is minimum value.
		loop i from: 0 to: n{
			building_block bb_to_build <- sorted_bb[i];
			ask bb_to_build {
				loop times: nb_build {
					do building_construction;
				}
			}
		}
	}
	
	
	reflex end_simulation when: current_date = 2050 and not batch_mode{
		do pause;
	}
	 

	action building_block_creation {
		if (not save_dist) {
			ask building_block {
				buildings <- building; //Create layer called buildings from building that overlap the building_block
				do build_empty_space;			}
		}
	}
}


species river {
	aspect geom {
		draw shape color: #blue;
	}
}

species river_line {
	aspect geom {
		draw shape color: #blue;
	}
}
species road {
	aspect geom {
		draw shape color: #yellow;
	}
}

species procedural_road {
	aspect geom {
		draw shape color: #grey;
	}
}

species CBD {
	aspect geom {
		draw circle(300) color: #cyan;
	}
}

species road_line {
	aspect geom {
		draw shape color: #red;
	}
}

species building {
	int build_year <- 2020; //Give current buildings a value not associated with simulation.
	string type;
	rgb color;
	aspect geom {
		draw shape color: color;
	}
}

species Cranfield {
	string type;
	aspect geom {
		draw shape color: #black;
	}
}


species building_block {
	rgb color <- #peru;
	list<building> buildings;
	geometry empty_space; //Create geometry object for empty space.
	bool possible_construction <- true ;  //boolean to determine if construction is possible.
	float free_space_rate;
	float Slope_Parc;
	float road_dist;
	float river_dist;
	float crit_roads;
	float crit_rivers;
	float crit_CBD;
	float crit_slope;
	float constructability;
	
	
	action build_empty_space {
		empty_space <- copy(shape); 
		loop bd over: buildings {
			empty_space <- empty_space - (bd); //
		}
		
		if (empty_space != nil) {
			list<geometry> geoms_to_keep <- empty_space.geometries where (each != nil and each.area > 0);
			if (not empty(geoms_to_keep)) {
				empty_space <- geometry(geoms_to_keep);
			} else {
				empty_space <- nil;
				possible_construction <- false;
			}
		}
	}
	
	action update_empty_space(building bd) {
		empty_space <- empty_space - (bd); //Remove buildings (with 2m buffer) from empty space
		//If empty spaces are not equal to nil then list their geometries greater than 200m2
		if (empty_space != nil) {
			list<geometry> geoms_to_keep <- empty_space.geometries where (each != nil and each.area > 200);
			if (not empty(geoms_to_keep)) {
				empty_space <- geometry(geoms_to_keep);
			} else {
				empty_space <- nil;
				possible_construction <- false;
			}
		}
	}
	
	action compute_criteria {
	

 
  	
   
   CBD closest_CBD <- CBD with_min_of(each distance_to self);
   crit_CBD <- closest_CBD distance_to self;
	
	//New slope criterion from Slope_Parc values.
	crit_slope <- Slope_Parc;
	
	//New roads criterion from NEAR_DIST values.
	crit_roads <- road_dist;
	
	//New roads criterion from NEAR_DIST values.
	crit_rivers <- river_dist;
	
		
	}
	//Compute building density, quantity of roads and rivers, and overall constructability.
	action compute_land_value {
		crit_roads <- ((crit_roads_max - crit_roads)/(crit_roads_max - crit_roads_min));
		crit_rivers <- crit_rivers / crit_rivers_max;
		crit_CBD <- ((crit_CBD_max - crit_CBD)/(crit_CBD_max - crit_CBD_min));
		crit_slope <- ((crit_slope_max - crit_slope)/(crit_slope_max - crit_slope_min)); 
		constructability <- (crit_CBD * w1 + crit_roads * w2 + crit_slope * w3 + crit_rivers * w4)/ (w1 + w2 + w3 + w4); 
	}

	
	//Action to create buildings.
	action building_construction  {
		float limit <- world.shape.area; //Limit building construction to world area
		list<building> possible_buildings <- (buildings); //Create a list called possible_buildings 
		if empty(possible_buildings) {
			possible_construction<- false;
			write name;
			return;
		}
		bool bd_built <- false; //Boolean to indicate if building_block has had construction in it.
		building bd <- nil;
		
		// Get one building from the possible buildings to use in construction
		loop while: true {
			building one_building <- one_of (possible_buildings where (envelope(each.shape).area < limit));
			if (one_building = nil) {
				break;
			}
			geometry new_building <- copy(one_building.shape); //Copy the selected building to create a new_building variable
			float size <- min([new_building.width,new_building.height]); //Get the area of the new_building.
			
			geometry space <- empty_space - size; //Remove area of building from empty_space.
			//If space space is not equal to nothing and greater in area than 0.0. 
			if ((space != nil) and (space.area > 0.0)) {
				agent closest_road_river <- (procedural_road) closest_to space; //Create closest_road_river agent using the road closest to space.
				create building with:[ shape:: new_building ,  location::((closest_road_river closest_points_with space)[1]), location::centroid(space), type::one_building.type] {
					myself.buildings << self;
					color <- building_color[type];
					build_year <- current_date.year; //Add simulation year to attribute table (build_year column).
					bd <- self;
					if (build_year <= 2025) {
						type <- twenties1;
					} else if (build_year <= 2030) {
						type <- twenties2;
					} else if (build_year <= 2035) {
						type <- thirties1;
					} else if (build_year <= 2040) {
						type <- thirties2;
					} else if (build_year <= 2045) {
						type <- forties1;
					} else if (build_year <= 2050) {
						type <- forties2;
					}
					color <- building_color[type];
					
				}
				bd_built <- true;
				break;
			} else {
				limit <- envelope(one_building.shape).area;
			}
		}
		
		if (bd_built) {
			do update_empty_space(bd);
			possible_construction<- false;  //Don't allow any further buildings to be built in the same block.
		}
	}
	
	aspect geom {
		draw shape color:color border: #black;
	}
action type_creation {
	
	
}
}





experiment Urban_Growth_Simulation type: gui {
	parameter "weight for the distance to the CBDs" var:w1 min: 0.0 max: 1.0;
	parameter "weight for the road distance criterion" var:w2 min: 0.0 max: 1.0;
	parameter "weight for the slope criterion" var:w3 min: 0.0 max: 1.0;
	parameter "weight for the river distance criterion" var:w4 min: 0.0 max: 1.0;
	
	output {
		display "map" type: opengl ambient_light: 100{
			species Cranfield aspect: geom;
			species building_block aspect: geom;
			species river aspect: geom;
			species river_line aspect: geom;
			species road aspect: geom;
			species building aspect: geom;	
		}
	}
	reflex save_result {
		save building to:"../results/buildings.shp" type:"shp" attributes: ["ID":: int(self), "TYPE"::type, "YEAR"::build_year]; 
		
		}
}


experiment Optimization type: batch keep_seed: true repeat: 5 until: ( date = 2010 ) {
	parameter "batch mode" var: batch_mode <- true;
	list<float> vals;
	parameter "weight for the density criterion" var:w1 min: 0.0 max: 1.0 step: 0.1; 
	parameter "weight for the distance to services (education, religion, economic)" var:w2 min: 0.0 max: 1.0 step: 0.1;
	
	method genetic pop_dim: 5 crossover_prob: 0.7 mutation_prob: 0.1 nb_prelim_gen: 1 max_gen: 500  minimize: error ;
	
	reflex save_result {
		vals<< world.error;
		save (string(world.w1) + "," + world.w2 + "," + world.w2 + "," + world.error) to: "E:/GAMA/Workspace/results_vector.csv" type:"text"; 
		if (length(vals) = 5) {
			write "error: " + mean(vals) + " for parameters: w1 = " + w1 + "  w2 = " + w2 ;
			vals <- [];
		}
	}
}

experiment save_distances type: gui {
	parameter "save distances" var: save_dist <- true;
	output {}
}
