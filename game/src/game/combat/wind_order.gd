class_name BWWindOrder
extends RefCounted
## D390: the playback order of wind motion around a blow (presentation only;
## the rules already resolved it, D365-D370). The author: when wind DRAWS IN,
## show the motion first, then the hit; when it PUSHES OUT, the hit first,
## then the motion.
##
## The rules already emit a skill's Draw in before its hits (BWWind.pre_mode)
## and every push after them (BWWindShape.post, gust fields). Two pulls still
## land after the blow in the event stream: a Vortex basic's pull on its
## target (BWWind.after_basic) and a Vortex field the blow's paint fires
## (field_fire + its pulls, Eye of the Vortex's eye_pull). hoist() moves
## those in front of the blow they belong to, with the slams that
## follow each pulled unit. Pushes are never moved.
##
## The combat screen calls hoist() on its queue before it drains it.

## Events that carry blows (BWCutsceneTier.BLOW_EVENTS).
const BLOWS := ["attack", "counter", "riposte", "skill"]
## Events that close an action's tail ("growth" does not: a basic's pull lands after it).
const ENDS := ["turn", "cycle", "battle_end", "group_turn", "group_end"]


static func is_pull(e: Dictionary) -> bool:
	return str(e.get("type", "")) == "move" and str(e.get("kind", "")) == "pull" and bool(e.get("wind", false))


## A pure reorder of an event list (a new Array; the input is untouched).
static func hoist(events: Array) -> Array:
	var out: Array = events.duplicate()
	var i := 0
	while i < out.size():
		var e: Dictionary = out[i]
		if not str(e.get("type", "")) in BLOWS or _is_later_strike(e):
			i += 1
			continue
		# the blow's tail: its later strikes, riders, paints, field fires ...
		var take: Array = []                  # indices to hoist, in order
		var j := i + 1
		while j < out.size():
			var q: Dictionary = out[j]
			var t := str(q.get("type", ""))
			if t in ENDS or (t in BLOWS and not _is_later_strike(q)):
				break
			if is_pull(q):
				take.append(j)
				# its own slam right behind it rides along
				var uid := str(q.get("unit", ""))
				var k := j + 1
				while k < out.size():
					var r: Dictionary = out[k]
					var rt := str(r.get("type", ""))
					if str(r.get("unit", "")) == uid and rt == "slam":
						take.append(k)
						k += 1
					else:
						break
				j = k
				continue
			if (t == "field_fire" and str(q.get("mode", "")) == "vortex") or t == "eye_pull":
				take.append(j)
			j += 1
		if take.is_empty():
			i += 1
			continue
		var moved: Array = []
		for k in range(take.size() - 1, -1, -1):
			moved.push_front(out[take[k]])
			out.remove_at(take[k])
		for k in moved.size():
			out.insert(i + k, moved[k])
		i += moved.size() + 1
	return out


static func _is_later_strike(e: Dictionary) -> bool:
	return str(e.get("type", "")) == "attack" and int(e.get("strike", 0)) > 0
