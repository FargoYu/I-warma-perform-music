extends RefCounted
## Pure support facts. Local contact, attachment and anchored ancestry differ.
const Bounds = preload("res://objects/physics/logical_bounds.gd")
var links: Dictionary = {}

func rebuild(state: Dictionary, roles: Dictionary, detached: Array = [], intents: Dictionary = {}) -> void:
	links.clear()
	var ids := state.keys()
	ids.sort()
	for id in ids:
		if roles[id] in ["terrain", "elevator"]:
			continue
		var contacts: Array = []
		for other in ids:
			if other != id and state[id].bottom() == state[other].top() and Bounds.cross_overlap(state[id], state[other], 1):
				contacts.append(other)
		# Highest prospective support wins (smallest down-positive Y request).
		# A stationary floor thus keeps a bridge rider when another support falls.
		# Equal requests use stable semantic IDs; never SceneTree callback order.
		contacts.sort_custom(func(a, b):
			var ay := float(intents.get(a, {}).get("dy", 0.0))
			var by := float(intents.get(b, {}).get("dy", 0.0))
			return a < b if ay == by else ay < by)
		links[id] = {"contacts": contacts, "local_contact": not contacts.is_empty(),
			"support": contacts[0] if not contacts.is_empty() else "", "plane": state[id].bottom(),
			"attached": not contacts.is_empty() and id not in detached, "carry_x": false, "carry_y": true}

func anchored(id: String, roles: Dictionary) -> bool:
	var seen: Array = []
	while roles.has(id):
		if roles[id] in ["terrain", "elevator"]:
			return true
		if id in seen or not links.has(id) or not links[id].attached:
			return false
		seen.append(id)
		id = links[id].support
	return false

func required_offsets(source: String, state: Dictionary) -> Dictionary:
	var offsets: Dictionary = {source: 0.0}
	var queue: Array = [source]
	var ids := links.keys()
	ids.sort()
	while not queue.is_empty():
		var parent: String = queue.pop_front()
		for id in ids:
			if not offsets.has(id) and links[id].attached and links[id].carry_y and links[id].support == parent:
				offsets[id] = float(offsets[parent]) - state[id].height
				queue.append(id)
	return offsets
