extends RefCounted
## Extract exact occupied cells from a real TileMapLayer. Never edits its TileSet.
const Bounds = preload("res://objects/physics/logical_bounds.gd")
const Geometry = preload("res://objects/physics/scene_geometry.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")

static func cells(layer: TileMapLayer, owner: Node) -> Dictionary:
	if not Geometry.translation_only(layer):
		return Contract.failure("unsupported_transform")
	var tiles := layer.tile_set
	if tiles == null or tiles.tile_size != Vector2i(16, 16) or tiles.get_physics_layers_count() != 1 or not layer.collision_enabled:
		return Contract.failure("unsupported_tileset")
	if tiles.get_physics_layer_collision_layer(0) != 1:
		return Contract.failure("unexpected_collision_identity")
	var records: Array = []
	var base := str(owner.get_path_to(layer))
	for cell in layer.get_used_cells():
		var data := layer.get_cell_tile_data(cell)
		if data == null or data.get_collision_polygons_count(0) != 1 or data.is_collision_polygon_one_way(0, 0):
			return Contract.failure("unsupported_tile_shape", {"cell": str(cell)})
		if not Geometry.rectangle_polygon(data.get_collision_polygon_points(0, 0), Rect2(-8, -8, 16, 16)):
			return Contract.failure("terrain_requires_exact_instance", {"cell": str(cell)})
		# This initial adapter supports the audited atlas tile and no transformed alternatives.
		if layer.get_cell_source_id(cell) != 0 or layer.get_cell_atlas_coords(cell) != Vector2i.ZERO or layer.get_cell_alternative_tile(cell) != 0:
			return Contract.failure("unsupported_tile_identity", {"cell": str(cell)})
		var center := layer.to_global(layer.map_to_local(cell))
		var id := "%s/cell(%d,%d)/0:0,0:0" % [base, cell.x, cell.y]
		records.append({"id": id, "node": layer, "role": "terrain", "cell": cell,
			"rect": Bounds.new(float(center.x) - 8.0, float(center.y) - 8.0, 16.0, 16.0),
			"local_origin": Vector2.ZERO, "layer": tiles.get_physics_layer_collision_layer(0),
			"mask": tiles.get_physics_layer_collision_mask(0)})
	return {"ok": true, "records": records}
