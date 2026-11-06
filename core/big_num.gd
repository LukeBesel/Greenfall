class_name BigNum
extends RefCounted
## Arbitrary-magnitude non-negative-friendly number: value = mantissa * 10^exponent.
## Mantissa is kept in [1, 10) (or 0). Operations return new BigNum instances.
## Precision is that of a float mantissa (~15 digits), which is plenty for an incremental game.

enum Format { SHORT, SCIENTIFIC, ENGINEERING }

const SHORT_SUFFIXES: Array[String] = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
## When two numbers differ by more than this many orders of magnitude, the smaller is ignored in add/sub.
const PRECISION_GAP: int = 17

var mantissa: float = 0.0
var exponent: int = 0


func _init(m: float = 0.0, e: int = 0) -> void:
	mantissa = m
	exponent = e
	_normalize()


static func from_float(v: float) -> BigNum:
	return BigNum.new(v, 0)


static func zero() -> BigNum:
	return BigNum.new(0.0, 0)


static func from_serialized(data: Variant) -> BigNum:
	if data is Array and (data as Array).size() == 2:
		var arr: Array = data
		return BigNum.new(float(arr[0]), int(arr[1]))
	if data is float or data is int:
		return BigNum.from_float(float(data))
	return BigNum.zero()


func serialize() -> Array:
	return [mantissa, exponent]


func copy() -> BigNum:
	return BigNum.new(mantissa, exponent)


func _normalize() -> void:
	if mantissa == 0.0 or is_nan(mantissa):
		mantissa = 0.0
		exponent = 0
		return
	if is_inf(mantissa):
		mantissa = 9.999999 if mantissa > 0.0 else -9.999999
		exponent = 999999
		return
	var a: float = absf(mantissa)
	var shift: int = int(floor(log(a) / log(10.0)))
	if shift != 0:
		mantissa = mantissa / pow(10.0, shift)
		exponent += shift
	# Guard against float rounding leaving mantissa at 10.0 or just below 1.0
	a = absf(mantissa)
	if a >= 10.0:
		mantissa /= 10.0
		exponent += 1
	elif a < 1.0:
		mantissa *= 10.0
		exponent -= 1


func is_zero() -> bool:
	return mantissa == 0.0


func to_float() -> float:
	if exponent > 308:
		return INF if mantissa > 0.0 else -INF
	return mantissa * pow(10.0, exponent)


func add(other: BigNum) -> BigNum:
	if other.is_zero():
		return copy()
	if is_zero():
		return other.copy()
	var diff: int = exponent - other.exponent
	if diff > PRECISION_GAP:
		return copy()
	if diff < -PRECISION_GAP:
		return other.copy()
	if diff >= 0:
		return BigNum.new(mantissa + other.mantissa / pow(10.0, diff), exponent)
	return BigNum.new(other.mantissa + mantissa / pow(10.0, -diff), other.exponent)


func sub(other: BigNum) -> BigNum:
	return add(BigNum.new(-other.mantissa, other.exponent))


func mul(other: BigNum) -> BigNum:
	return BigNum.new(mantissa * other.mantissa, exponent + other.exponent)


func mul_f(f: float) -> BigNum:
	return BigNum.new(mantissa * f, exponent)


func div(other: BigNum) -> BigNum:
	if other.is_zero():
		push_error("BigNum division by zero")
		return BigNum.zero()
	return BigNum.new(mantissa / other.mantissa, exponent - other.exponent)


func add_f(f: float) -> BigNum:
	return add(BigNum.from_float(f))


## Returns -1, 0, 1.
func compare(other: BigNum) -> int:
	var sa: int = signi(int(sign(mantissa)))
	var sb: int = signi(int(sign(other.mantissa)))
	if sa != sb:
		return 1 if sa > sb else -1
	if sa == 0:
		return 0
	if exponent != other.exponent:
		var r: int = 1 if exponent > other.exponent else -1
		return r * sa
	if is_equal_approx(mantissa, other.mantissa):
		return 0
	return 1 if mantissa > other.mantissa else -1


func gte(other: BigNum) -> bool:
	return compare(other) >= 0


func lt(other: BigNum) -> bool:
	return compare(other) < 0


## log10 of the value (for ratios, progress bars, time estimates).
func log10() -> float:
	if mantissa <= 0.0:
		return -INF
	return log(mantissa) / log(10.0) + exponent


## Ratio self/other as float, clamped to a sane range (for progress bars).
func ratio_to(other: BigNum) -> float:
	if other.is_zero():
		return 1.0
	var d: BigNum = div(other)
	if d.exponent > 6:
		return 1.0e6
	if d.exponent < -12:
		return 0.0
	return d.to_float()


func format(fmt: int = Format.SHORT, decimals: int = 2) -> String:
	if is_zero():
		return "0"
	var neg: bool = mantissa < 0.0
	var s: String = _format_abs(absf(mantissa), exponent, fmt, decimals)
	return ("-" + s) if neg else s


static func _format_abs(m: float, e: int, fmt: int, decimals: int) -> String:
	if e < 3:
		var v: float = m * pow(10.0, e)
		if e < 0:
			return String.num(v, decimals)
		# Whole-number display below 1000, but keep one decimal for small fractional values.
		if v < 10.0 and not is_equal_approx(v, round(v)):
			return String.num(v, 1)
		return str(int(floor(v + 0.000001)))
	match fmt:
		Format.SCIENTIFIC:
			return "%se%d" % [String.num(m, decimals), e]
		Format.ENGINEERING:
			var eng: int = int(floor(e / 3.0)) * 3
			return "%se%d" % [String.num(m * pow(10.0, e - eng), decimals), eng]
		_:
			var group: int = int(floor(e / 3.0))
			var scaled: float = m * pow(10.0, e - group * 3)
			return "%s%s" % [_trim(String.num(scaled, decimals)), _suffix(group)]


static func _trim(s: String) -> String:
	if s.find(".") == -1:
		return s
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s


static func _suffix(group: int) -> String:
	if group < SHORT_SUFFIXES.size():
		return SHORT_SUFFIXES[group]
	# After Dc: aa, ab, ... zz, then fall back to e-notation-like marker.
	var idx: int = group - SHORT_SUFFIXES.size()
	if idx < 26 * 26:
		var a: int = idx / 26
		var b: int = idx % 26
		return String.chr(97 + a) + String.chr(97 + b)
	return "e%d" % (group * 3)


func _to_string() -> String:
	return format(Format.SCIENTIFIC, 3)
