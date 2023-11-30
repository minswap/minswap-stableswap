use aiken/builtin
use aiken/bytearray
use aiken/cbor
use aiken/dict
use aiken/list
use aiken/string
use aiken/transaction.{Datum, DatumHash, InlineDatum, NoDatum}
use stableswap/types.{DatumMap}

const minus_ascii_code = 45

const zero_ascii_code = 48

pub fn sum_ints(arr: List<Int>) -> Int {
  list.reduce(arr, 0, fn(acc, a) { a + acc })
}

test test_sum_ints() {
  let arr =
    [1, 2, 3]
  sum_ints(arr) == 6
}

pub fn abs(i: Int) -> Int {
  if i >= 0 {
    i
  } else {
    0 - i
  }
}

test test_abs() {
  abs(0) == 0 && abs(1) == 1 && abs(-1) == 1
}

pub fn bytearray_to_int(byte_arr: ByteArray) -> Int {
  let byte_len = bytearray.length(byte_arr)
  do_bytearray_to_int(byte_arr, 0, 0, byte_len)
}

pub fn do_bytearray_to_int(
  byte_arr: ByteArray,
  idx: Int,
  acc: Int,
  byte_len: Int,
) -> Int {
  if idx == byte_len {
    acc
  } else {
    let byte = builtin.index_bytearray(byte_arr, idx)
    if idx == 0 && byte == minus_ascii_code {
      do_bytearray_to_int(byte_arr, idx + 1, acc, byte_len) * -1
    } else if byte < zero_ascii_code || byte > zero_ascii_code + 9 {
      fail
    } else {
      do_bytearray_to_int(
        byte_arr,
        idx + 1,
        acc * 10 + ( byte - zero_ascii_code ),
        byte_len,
      )
    }
  }
}

test test_bytearray_to_int() {
  let r1 = bytearray_to_int(string.to_bytearray(@"123"))
  let r2 = bytearray_to_int(string.to_bytearray(@"111"))
  r1 == 123 && r2 == 111
}

// This function with zip 2 list with @predicate condition
// It expects 2 lists must having the same length, otherwise it will throw error
pub fn zip_with(
  arr1: List<a>,
  arr2: List<a>,
  predicate: fn(a, a) -> result,
) -> List<result> {
  when arr1 is {
    [] ->
      when arr2 is {
        [] ->
          []
        _ -> fail
      }
    [x, ..xs] ->
      when arr2 is {
        [] -> fail
        [y, ..ys] ->
          [predicate(x, y), ..zip_with(xs, ys, predicate)]
      }
  }
}

test test_zip_with() {
  let arr1 =
    [1, 2, 3]
  let arr2 =
    [4, 5, 6]
  let z1 = zip_with(arr1, arr2, fn(a1, a2) { a1 + a2 })
  let z2 = zip_with(arr1, arr2, fn(a1, a2) { a1 * a2 })
  z1 == [5, 7, 9] && z2 == [4, 10, 18]
}

test test_zip_with_throw_err_1() fail {
  let arr1 =
    [1, 2, 3]
  let arr2 =
    [4, 5, 6, 6]
  let x = zip_with(arr1, arr2, fn(a1, a2) { a1 + a2 })
  trace cbor.diagnostic(x)
  True
}

test test_zip_with_throw_err_2() fail {
  let arr1 =
    [1, 2, 3]
  let arr2 =
    [4, 5, 6, 6]
  let x = zip_with(arr2, arr1, fn(a1, a2) { a1 + a2 })
  trace cbor.diagnostic(x)
  True
}

pub fn verify_positive_ints(arr: List<Int>) -> Bool {
  list.all(arr, fn(a) { a > 0 })
}

test test_verify_positive_ints() {
  let arr1 =
    [1, 2, 3]
  let arr2 =
    [-1, 2, 3]
  let arr3 =
    [0, 2, 3]
  let arr4 =
    [-1, 0, 1]
  let r1 = verify_positive_ints(arr1)
  let r2 = verify_positive_ints(arr2)
  let r3 = verify_positive_ints(arr3)
  let r4 = verify_positive_ints(arr4)
  r1 && !r2 && !r3 && !r4
}

// This function will make sure amounts are non-negative numbers and having positive sum
pub fn verify_non_negative_amounts(arr: List<Int>) -> Bool {
  let is_non_negative = list.all(arr, fn(a) { a >= 0 })
  let sum = list.reduce(arr, 0, fn(acc, a) { acc + a })
  is_non_negative && sum > 0
}

test test_verify_non_negative_amounts() {
  let arr1 =
    [1, 2, 3]
  let arr2 =
    [-1, 2, 3]
  let arr3 =
    [0, 2, 3]
  let arr4 =
    [-1, 0, 1]
  let arr5 =
    [0, 0, 0]
  let r1 = verify_non_negative_amounts(arr1)
  let r2 = verify_non_negative_amounts(arr2)
  let r3 = verify_non_negative_amounts(arr3)
  let r4 = verify_non_negative_amounts(arr4)
  let r5 = verify_non_negative_amounts(arr5)
  r1 && !r2 && r3 && !r4 && !r5
}

pub fn compare_list_with(
  arr1: List<Int>,
  arr2: List<Int>,
  predicate: fn(Int, Int) -> Bool,
) -> Bool {
  when arr1 is {
    [] ->
      when arr2 is {
        [] -> True
        _ -> False
      }
    [x, ..xs] ->
      when arr2 is {
        [] -> False
        [y, ..ys] -> predicate(x, y) && compare_list_with(xs, ys, predicate)
      }
  }
}

test test_compare_list_with() {
  let arr1 =
    [1, 2, 3]
  let arr2 =
    [1, 2, 4]
  let arr3 =
    [2, 3, 4]
  let arr4 =
    [1, 2, 3, 4]
  let r1 = compare_list_with(arr1, arr2, fn(a1, a2) { a1 <= a2 })
  let r2 = compare_list_with(arr1, arr3, fn(a1, a2) { a1 < a2 })
  let r3 = compare_list_with(arr1, arr4, fn(a1, a2) { a1 <= a2 })
  let r4 = compare_list_with(arr4, arr1, fn(a1, a2) { a1 == a2 })
  let not_over_slippage =
    compare_list_with(
      [10, 10, 10],
      // real
      [10, 10, 11],
      // minimumAmount
      fn(actual, expt) { actual >= expt },
    )
  r1 && r2 && !r3 && !not_over_slippage && !r4
}

pub fn list_at_index(outputs: List<a>, payout_outputs_offset: Int) -> a {
  if payout_outputs_offset >= 5 {
    outputs
      |> skip_5_items
      |> list_at_index(payout_outputs_offset - 5)
  } else {
    list_at_index_step(outputs, payout_outputs_offset)
  }
}

pub fn list_at_index_step(outputs: List<a>, current_index: Int) -> a {
  expect current_index >= 0
  if current_index == 0 {
    expect [output, ..] = outputs
    output
  } else {
    outputs
      |> builtin.tail_list
      |> list_at_index_step(current_index - 1)
  }
}

/// Small utility to skip 5 items in a list.
/// Used by `list_at_index`.
fn skip_5_items(some_list: List<a>) -> List<a> {
  some_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
    |> builtin.tail_list
}

/// big batch will have 8 order utxo, 1 pool utxo, some batcher utxo(usually is 1)
test test_list_at_index_utxo_length() {
  let arr =
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  expect list_at_index(arr, 0) == 0
  expect list_at_index(arr, 1) == 1
  expect list_at_index(arr, 2) == 2
  expect list_at_index(arr, 3) == 3
  expect list_at_index(arr, 4) == 4
  expect list_at_index(arr, 5) == 5
  expect list_at_index(arr, 6) == 6
  expect list_at_index(arr, 7) == 7
  expect list_at_index(arr, 8) == 8
  expect list_at_index(arr, 9) == 9
  True
}

/// list of length almost is 2 or 3
test test_list_at_index_assets_length() {
  let arr =
    [0, 1, 2]
  expect list_at_index(arr, 0) == 0
  expect list_at_index(arr, 1) == 1
  expect list_at_index(arr, 2) == 2
  True
}

test test_list_at_index_step_assets_length() {
  let arr =
    [0, 1, 2]
  expect list_at_index_step(arr, 0) == 0
  expect list_at_index_step(arr, 1) == 1
  expect list_at_index_step(arr, 2) == 2
  True
}

test test_list_at_index_step_negative_index_err() fail {
  let arr =
    [0, 1, 2]
  list_at_index_step(arr, -1) == 0
}

test test_list_at_index_negative_index_err() fail {
  let arr =
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  list_at_index(arr, -1) == 0
}

test test_list_at_index_index_higher_length_err() fail {
  let arr =
    [0, 1, 2]
  list_at_index(arr, 3) == 0
}

pub fn compare_list_length(arr1: List<a>, arr2: List<b>) -> Bool {
  when arr1 is {
    [] -> arr2 == []
    _ ->
      when arr2 is {
        [] -> False
        _ ->
          compare_list_length(
            arr1 |> builtin.tail_list,
            arr2 |> builtin.tail_list,
          )
      }
  }
}

test test_compare_list_length() {
  let arr1 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  let arr2 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  compare_list_length(arr1, arr2)
}

test test_compare_list_length_1() {
  let arr1 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
  let arr2 =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
  and {
    !compare_list_length(arr1, arr2),
    !compare_list_length(arr2, arr1),
  }
}

test test_compare_list_length_2() {
  compare_list_length([], [])
}

test test_compare_list_length_3() {
  let arr1 =
    [1]
  let arr2 =
    []
  and {
    !compare_list_length(arr1, arr2),
    !compare_list_length(arr2, arr1),
  }
}

fn contains_element(list: List<a>, elem: a) -> Bool {
  when list is {
    [] -> False
    [x, ..xs] -> elem == x || contains_element(xs, elem)
  }
}

pub fn is_list_unique(list: List<a>) -> Bool {
  when list is {
    [] -> True
    [_] -> True
    [x, ..xs] -> !contains_element(xs, x) && is_list_unique(xs)
  }
}

test test_is_list_unique() {
  let arr1 =
    []
  let arr2 =
    [10]
  let arr3 =
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  let arr4 =
    [0, 0, 2, 3, 4, 5, 6, 7, 8, 9]
  and {
    is_list_unique(arr1),
    is_list_unique(arr2),
    is_list_unique(arr3),
    !is_list_unique(arr4),
  }
}

pub fn must_find_script_datum(datums: DatumMap, datum: Datum) -> Data {
  let datum_opt =
    when datum is {
      NoDatum -> None
      DatumHash(dh) ->
        datums
          |> dict.get(dh)
      InlineDatum(dat) -> Some(dat)
    }
  expect Some(datum) = datum_opt
  datum
}
