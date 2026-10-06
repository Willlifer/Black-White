class_name BWBarks
## Picks a bark line per design/BARKS.md: match event (+ action), speaker
## friendliness, trust stage, and the other party's friendliness; pair-
## specific lines weigh 3× over `any`; if a pool is empty, step the trust
## stage toward `acquainted` and try again. Deterministic given the rng.

const PAIR_WEIGHT := 3
const STAGES := ["strangers", "acquainted", "trusted"]


static func pick(event: String, speaker: String, trust: String, toward: String = "any",
		action: String = "", rng: RandomNumberGenerator = null) -> Dictionary:
	var tries: Array = [trust]
	if trust != "acquainted":
		tries.append("acquainted")
	for t in STAGES:
		if not t in tries:
			tries.append(t)
	for t in tries:
		var pool: Array = []
		for b in BWData.table("barks"):
			if b.event != event or b.speaker_friendliness != speaker or b.trust != t:
				continue
			if action != "" and str(b.action) != action:
				continue
			if b.toward_friendliness == toward and toward != "any":
				for i in PAIR_WEIGHT:
					pool.append(b)
			elif b.toward_friendliness == "any":
				pool.append(b)
		if not pool.is_empty():
			var i := rng.randi() % pool.size() if rng else randi() % pool.size()
			return pool[i]
	return {}


## "{speaker}" etc. filled in from a context dictionary.
static func fill(line: String, ctx: Dictionary) -> String:
	var out := line
	for k in ctx:
		out = out.replace("{%s}" % k, str(ctx[k]))
	return out


static func clip_path(clip: String) -> String:
	return "res://audio/barks/%s.wav" % clip.to_lower().replace(" ", "_")
