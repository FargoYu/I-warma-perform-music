extends RefCounted
## Localize the one audited legacy atlas tile; never relax TerrainAdapter validation.
const Adapter = preload("res://objects/physics/terrain_adapter.gd")
const Geometry = preload("res://objects/physics/scene_geometry.gd")
const Contract = preload("res://objects/physics/motion_contract.gd")

static func prepare(layer: TileMapLayer, room: Node) -> Dictionary:
	var shared := layer.tile_set
	if shared == null or shared.tile_size != Vector2i(16,16) or shared.get_physics_layers_count() != 1 or shared.get_source_count() != 1 or shared.get_source_id(0) != 0:
		return Contract.failure("unsupported_authored_tileset")
	var source := shared.get_source(0) as TileSetAtlasSource
	if source == null or source.get_tiles_count() != 1 or source.get_tile_id(0) != Vector2i.ZERO or source.get_alternative_tiles_count(Vector2i.ZERO) != 1:
		return Contract.failure("unsupported_authored_atlas")
	var data := source.get_tile_data(Vector2i.ZERO,0)
	if data.get_collision_polygons_count(0) != 1 or data.is_collision_polygon_one_way(0,0):
		return Contract.failure("unsupported_authored_collision")
	var polygon := data.get_collision_polygon_points(0,0)
	var legacy := PackedVector2Array([Vector2(-8,-7.99),Vector2(8,-7.99),Vector2(8,7.99),Vector2(-8,7.99)])
	if polygon != legacy and not Geometry.rectangle_polygon(polygon,Rect2(-8,-8,16,16)):
		return Contract.failure("unexpected_authored_polygon")
	var local := shared.duplicate(true) as TileSet
	var local_source := local.get_source(0) as TileSetAtlasSource
	if local == shared or local_source == source:
		return Contract.failure("terrain_copy_not_independent")
	local_source.get_tile_data(Vector2i.ZERO,0).set_collision_polygon_points(0,0,
		PackedVector2Array([Vector2(-8,-8),Vector2(8,-8),Vector2(8,8),Vector2(-8,8)]))
	layer.tile_set = local
	# The existing adapter is the authority for cells, identities and exact bounds.
	var validated := Adapter.cells(layer,room)
	if not validated.ok:
		return validated
	layer.update_internals()
	return {"ok":true}
