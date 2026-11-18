extends GutTest


func test_normalizes() -> void:
	var n := BigNum.new(1234.0, 0)
	assert_almost_eq(n.mantissa, 1.234, 0.0001)
	assert_eq(n.exponent, 3)


func test_add_and_sub() -> void:
	var a := BigNum.from_float(950.0)
	var b := BigNum.from_float(75.0)
	assert_almost_eq(a.add(b).to_float(), 1025.0, 0.001)
	assert_almost_eq(a.sub(b).to_float(), 875.0, 0.001)


func test_add_ignores_tiny() -> void:
	var big := BigNum.new(1.0, 40)
	var tiny := BigNum.from_float(1.0)
	assert_eq(big.add(tiny).exponent, 40)


func test_mul_div() -> void:
	var a := BigNum.new(2.0, 30)
	var b := BigNum.new(5.0, 10)
	var m := a.mul(b)
	assert_eq(m.exponent, 41)
	assert_almost_eq(m.mantissa, 1.0, 0.0001)
	assert_almost_eq(m.div(b).mantissa, 2.0, 0.0001)


func test_compare() -> void:
	assert_true(BigNum.new(1.0, 20).gte(BigNum.new(9.9, 19)))
	assert_true(BigNum.from_float(3.0).lt(BigNum.from_float(4.0)))
	assert_eq(BigNum.from_float(7.0).compare(BigNum.from_float(7.0)), 0)
	assert_true(BigNum.from_float(-5.0).lt(BigNum.zero()))


func test_beyond_int64() -> void:
	var n := BigNum.new(1.0, 30)
	for i: int in 10:
		n = n.mul(BigNum.new(1.0, 30))
	assert_eq(n.exponent, 330)
	assert_false(n.is_zero())


func test_format_short() -> void:
	assert_eq(BigNum.from_float(999.0).format(), "999")
	assert_eq(BigNum.from_float(1500.0).format(), "1.5K")
	assert_eq(BigNum.from_float(2_340_000.0).format(), "2.34M")
	assert_eq(BigNum.new(1.0, 36).format(), "1aa")
	assert_eq(BigNum.zero().format(), "0")


func test_format_sci_eng() -> void:
	assert_eq(BigNum.from_float(12345.0).format(BigNum.Format.SCIENTIFIC), "1.23e4")
	assert_eq(BigNum.from_float(12360.0).format(BigNum.Format.ENGINEERING), "12.36e3")


func test_serialize_roundtrip() -> void:
	var n := BigNum.new(4.56, 123)
	var back := BigNum.from_serialized(n.serialize())
	assert_eq(back.exponent, 123)
	assert_almost_eq(back.mantissa, 4.56, 0.0001)
