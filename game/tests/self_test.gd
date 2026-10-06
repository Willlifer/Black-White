class_name BWSelfTest
extends RefCounted
## The project's deterministic self-test (`-- --self-test`). Finds every
## res://tests/test_*.gd, runs each `test_*` method, and returns a structured
## report. Exit code is the number of failed suites, capped at 1 for the
## process (0 = all green).
##
## A test method receives a BWCheck and calls ok()/eq()/near() on it. A test
## that raises a script error shows up as a failure with no checks recorded.

const TEST_DIR := "res://tests/"


class BWCheck:
	extends RefCounted
	var failures: PackedStringArray = []
	var count := 0

	func ok(cond: bool, what: String) -> void:
		count += 1
		if not cond:
			failures.append(what)

	func eq(got: Variant, want: Variant, what: String) -> void:
		count += 1
		if typeof(got) != typeof(want) and not (_num(got) and _num(want)):
			failures.append("%s: got %s (%s), want %s" % [what, got, type_string(typeof(got)), want])
		elif got != want:
			failures.append("%s: got %s, want %s" % [what, got, want])

	func near(got: float, want: float, eps: float, what: String) -> void:
		count += 1
		if absf(got - want) > eps:
			failures.append("%s: got %.4f, want %.4f ±%s" % [what, got, want, eps])

	func _num(v: Variant) -> bool:
		return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func run() -> Dictionary:
	var started := Time.get_ticks_msec()
	var suites: Array = []
	var failed := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR))
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var script: GDScript = load(TEST_DIR + f)
		var suite := { "suite": f.get_basename(), "tests": [], "passed": true }
		if script == null or not script.can_instantiate():
			suite.passed = false
			suite.tests.append({ "name": "<load>", "passed": false, "failures": ["script failed to load"] })
		else:
			var inst: Object = script.new()
			for m in inst.get_method_list():
				var mname: String = m.name
				if not mname.begins_with("test_"):
					continue
				var c := BWCheck.new()
				inst.call(mname, c)
				var passed := c.failures.is_empty() and c.count > 0
				var t := { "name": mname, "passed": passed, "checks": c.count, "failures": Array(c.failures) }
				if c.count == 0:
					t.failures.append("no checks ran (script error?)")
				suite.tests.append(t)
				if not passed:
					suite.passed = false
		if not suite.passed:
			failed += 1
		suites.append(suite)
	var total := 0
	var total_failed := 0
	for s in suites:
		for t in s.tests:
			total += 1
			if not t.passed:
				total_failed += 1
	return {
		"project": "Black | White",
		"engine": Engine.get_version_info().string,
		"passed": failed == 0 and total > 0,
		"suites": suites.size(), "suites_failed": failed,
		"tests": total, "tests_failed": total_failed,
		"data_errors": Array(BWData.errors),
		"ms": Time.get_ticks_msec() - started,
		"results": suites,
	}


## Human summary for the console; the JSON goes to the report file.
static func summary(report: Dictionary) -> String:
	var lines: PackedStringArray = []
	for s in report.results:
		lines.append("%s %s" % ["PASS" if s.passed else "FAIL", s.suite])
		for t in s.tests:
			if not t.passed:
				for f in t.failures:
					lines.append("    ✗ %s: %s" % [t.name, f])
	lines.append("%d/%d tests passed in %d suites (%d ms)%s" % [
		report.tests - report.tests_failed, report.tests, report.suites, report.ms,
		"" if report.data_errors.is_empty() else ", %d DATA ERRORS" % report.data_errors.size()])
	for e in report.data_errors:
		lines.append("    data: " + e)
	return "\n".join(lines)
