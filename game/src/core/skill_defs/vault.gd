extends BWSkillDef
## Lance. D105 rework (the author: "I kept trying to use it and it felt
## horrible"): one click, no follow-up menu. Click an enemy 2..RANGE hexes
## away; you pole-vault over anything (units, rock, height) to the free hex
## beside it nearest you, leave your element on the takeoff hex, and strike
## at once with your weapon's basic attack (BWBattle.attack: its own
## enchantments, riposte answers, growth) carrying momentum +25% (D87, the
## `momentum` flag). Vault+: range PLUS_RANGE and momentum +35% (the flag's
## +25% times a PLUS_EXTRA_PCT% attack_mod held for that one blow).
## Replaces D87's dir heading + basic/Tridentpierce follow-up.

const RANGE := 3
const PLUS_RANGE := 4
const CD := 2
const PLUS_EXTRA_PCT := 8                  # 1.25 x 1.08 = 1.35
const NOWHERE := Vector2i(-9999, -9999)


func _init() -> void:
	define({
		"key": "vault", "name": "Vault", "weapon": "lance", "clip": "",
		"desc": "Click an enemy up to 3 tiles away: pole-vault over anything to its side, leave your element where you took off, and strike at once with +25% momentum",
		"plus": "Vault+: range 4, momentum +35%",
		"targeting": "unit", "needs_element": true, "range": RANGE, "cd": CD,
		"power": 0, "min_range": 2,
	}, 40)


func reach(u: BWUnit) -> int:
	return PLUS_RANGE if upgraded(u) else RANGE


func momentum_pct(u: BWUnit) -> int:
	var m := 1.0 + BWSkills.VAULT_MOMENTUM_PCT / 100.0
	if upgraded(u):
		m *= 1.0 + PLUS_EXTRA_PCT / 100.0
	return roundi((m - 1.0) * 100.0)


## Foes 2..reach away (no sight needed: it flies) with a free hex to land on.
func targets(b: BWBattle, u: BWUnit, _element: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for f in b.foes_of(u):
		var d := b.gap(u, f)
		if d < 2 or d > reach(u) or landing(b, u, f) == NOWHERE:
			continue
		for h in f.footprint():
			out.append(h)
	return out


## The free hex beside `f` nearest the vaulter, from which it can strike
## (melee reach, D31); ties by row, then column. NOWHERE if none.
func landing(b: BWBattle, u: BWUnit, f: BWUnit) -> Vector2i:
	var best := NOWHERE
	var foot := f.footprint()
	for h in BWHex.fringe(foot, 1):
		if h in foot or not b.board.exists(h) or not b.can_stand(u, h) or not b._reaches_unit(u, h, f, 1):
			continue
		if best == NOWHERE:
			best = h
			continue
		var dh := BWHex.distance(u.pos, h)
		var db := BWHex.distance(u.pos, best)
		if dh < db or (dh == db and (h.y < best.y or (h.y == best.y and h.x < best.x))):
			best = h
	return best


func plan(b: BWBattle, u: BWUnit, _element: String, target: Vector2i, p: Dictionary) -> void:
	var f := b.unit_at(target)
	if f == null or f.team == u.team:
		return
	var land := landing(b, u, f)
	if land == NOWHERE:
		return
	p.dest = land
	p.hexes = [u.pos]                      # the takeoff hex takes the element
	p["vault_foe"] = f
	var fc := strike_forecast(b, u, f)
	p.notes.append("Vault beside %s and strike at once: %d%% hit, %d damage (momentum +%d%%)" % [
		f.name, roundi(fc.hit.value), int(fc.damage.value), momentum_pct(u)])


## The basic strike's forecast with momentum on (read-only: restored after).
func strike_forecast(b: BWBattle, u: BWUnit, f: BWUnit) -> Dictionary:
	var had: bool = u.fx.get("momentum", false)
	u.fx["momentum"] = true
	var joined := _boost(b, u, true)
	var fc := b.forecast_basic(u, f)
	_boost(b, u, false, joined)
	if not had:
		u.fx.erase("momentum")
	return fc


## A leap: no fire crossing (D44).
func relocate(b: BWBattle, u: BWUnit, p: Dictionary, _target_hex: Vector2i) -> void:
	b.skill_relocate(u, p, [u.pos, p.dest], "leap")
	var f: BWUnit = p.get("vault_foe", null)
	if f != null:
		b._face(u, f.pos)


## After the takeoff hex is painted: the strike, a real basic attack.
func after_paint(b: BWBattle, u: BWUnit, _el: String, _target_hex: Vector2i, p: Dictionary,
		_results: Array, _stripped: int) -> void:
	var f: BWUnit = p.get("vault_foe", null)
	if f == null or not f.alive() or not b.in_range(u, f):
		return
	u.fx["momentum"] = true
	var joined := _boost(b, u, true)
	u.acted = false
	b.attack(u, f)
	u.acted = true
	_boost(b, u, false, joined)


## Vault+: the extra momentum as a one-blow attack_mod record (the battle
## reads attack mods only while some unit carries effects, hence _fx_units).
## Returns whether `u` had to join _fx_units, so the `off` call can leave it.
func _boost(b: BWBattle, u: BWUnit, on: bool, joined: bool = false) -> bool:
	if not upgraded(u):
		return false
	if on:
		u.effects.append({ "key": "attack_mod", "params": { "dmg_pct": PLUS_EXTRA_PCT }, "source": "vault_plus",
			"element": "", "kind": "skill", "rank": 1, "name": "Vault+ momentum" })
		if not u in b._fx_units:
			b._fx_units.append(u)
			return true
		return false
	u.effects = u.effects.filter(func(e): return e.source != "vault_plus")
	if joined:
		b._fx_units.erase(u)
	return false


## It strikes (through BWBattle.attack), so the AI weighs it: the strike's
## expected damage, +1000 for a likely finishing blow, plus the D86 arc.
func ai_considers(_row: Dictionary) -> bool:
	return true


func ai_score(b: BWBattle, u: BWUnit, pv: Dictionary) -> float:
	var best := 0.0
	for f in b.foes_of(u):
		if b.gap(u, f, pv.dest) > 1:
			continue
		var fc := strike_forecast(b, u, f)
		var ev: float = fc.expected.value
		best = maxf(best, ev + (1000.0 if ev >= f.hp else 0.0) + float(fc.get("arc_ev", 0.0)))
	return best


## D110: the confirm box shows the strike the vault makes.
func strike_preview(b: BWBattle, u: BWUnit, p: Dictionary) -> Dictionary:
	var f: BWUnit = p.get("vault_foe", null)
	if f == null:
		return {}
	return { "unit": f, "forecast": strike_forecast(b, u, f) }
