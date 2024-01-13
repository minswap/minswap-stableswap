use aiken/list
use stableswap/utils

fn do_d_converging(
  loops: Int,
  initial_value: Int,
  mul_balances: List<Int>,
  sum: Int,
  n: Int,
  ann: Int,
) -> Int {
  let dp =
    list.reduce(
      mul_balances,
      initial_value,
      fn(dpp, mul_balance) { dpp * initial_value / ( mul_balance * n ) },
    )
  let new_d =
    ( ann * sum + dp * n ) * initial_value / (
      ( ann - 1 ) * initial_value + ( n + 1 ) * dp
    )
  if utils.abs(new_d - initial_value) <= 1 || loops <= 1 {
    new_d
  } else {
    do_d_converging(loops - 1, new_d, mul_balances, sum, n, ann)
  }
}

pub fn get_d(mul_balances: List<Int>, amp: Int) -> Int {
  let sum = utils.sum_ints(mul_balances)
  if sum == 0 {
    0
  } else {
    let n = list.length(mul_balances)
    let ann = amp * n
    do_d_converging(255, sum, mul_balances, sum, n, ann)
  }
}

pub fn get_d_mem(balances: List<Int>, multiples: List<Int>, amp: Int) -> Int {
  let mul_balances = utils.zip_with(balances, multiples, fn(b, m) { b * m })
  get_d(mul_balances, amp)
}

fn do_get_y_converging(
  loops: Int,
  initial_value: Int,
  b: Int,
  c: Int,
  d: Int,
) -> Int {
  let next_value =
    ( initial_value * initial_value + c ) / ( 2 * initial_value + b - d )
  if utils.abs(next_value - initial_value) <= 1 || loops <= 1 {
    next_value
  } else {
    do_get_y_converging(loops - 1, next_value, b, c, d)
  }
}

pub fn get_y(i: Int, j: Int, x: Int, xp: List<Int>, amp: Int) -> Int {
  let n = list.length(xp)
  expect and {
      i != j,
      i >= 0,
      j >= 0,
      i < n,
      j < n,
    }
  let d = get_d(xp, amp)
  let ann = amp * n
  let (_, s, init_c) =
    list.foldl(
      xp,
      (0, 0, d),
      fn(y, acc) {
        let (index, sum, c) = acc
        if index == j {
          (index + 1, sum, c)
        } else {
          let temp_x =
            if index == i {
              x
            } else {
              y
            }
          (index + 1, sum + temp_x, c * d / ( temp_x * n ))
        }
      },
    )
  let b = s + d / ann
  let c = init_c * d / ( ann * n )
  do_get_y_converging(255, d, b, c, d)
}

test test_get_y() {
  let y = get_y(0, 1, 1100000, [1000000, 1000000], 2000)
  y == 900005
}

test test_get_d() {
  let d1 = get_d([1000000, 1000000], 2000)
  let d2 = get_d([9000000, 500000], 2000)
  let d3 = get_d([0, 0], 2000)
  d1 == 2000000 && d2 == 9490500 && d3 == 0
}

pub fn get_y_d(out_index: Int, xp: List<Int>, amp: Int, d: Int) -> Int {
  let n = list.length(xp)
  expect out_index >= 0 && out_index < n
  let ann = amp * n
  let (_, s, init_c) =
    list.foldl(
      xp,
      (0, 0, d),
      fn(y, acc) {
        let (index, sum, c) = acc
        if index == out_index {
          (index + 1, sum, c)
        } else {
          (index + 1, sum + y, c * d / ( y * n ))
        }
      },
    )
  let b = s + d / ann
  let c = init_c * d / ( ann * n )
  do_get_y_converging(255, d, b, c, d)
}

test test_get_y_d() {
  let y1 =
    get_y_d(1, [100000000000, 100000000000, 100000000000], 2000, 299999990000)
  let y2 =
    get_y_d(0, [50000050000, 49999950003, 50000000000], 2000, 149999990003)
  let y3 =
    get_y_d(2, [25000360001, 25000005009, 25000160000], 2000, 75000515010)
  let y4 =
    get_y_d(0, [100000000000, 100000000000, 100000000000], 2000, 299999990000)
  let y5 =
    get_y_d(2, [99999990001, 100000000000, 100000000000], 2000, 299999980001)
  let y6 =
    get_y_d(2, [99999960004, 99999980002, 99999970003], 2000, 299999900009)
  y1 == 99999990000 && y2 == 50000040000 && y3 == 25000150000 && y4 == 99999990000 && y5 == 99999990000 && y6 == 99999960003
}
