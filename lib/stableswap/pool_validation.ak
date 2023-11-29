use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/transaction.{Input, Output, ValidityRange}
use aiken/transaction/value.{PolicyId}
use stableswap/utils

pub fn validate_batcher_license(
  license_input: Input,
  validity_range: ValidityRange,
  license_policy_id: PolicyId,
  maximum_deadline_range: Int,
) -> Bool {
  let Input { output: Output { value: license_value, .. }, .. } = license_input
  expect [(license_asset_name, license_amount)] =
    license_value
      |> value.tokens(license_policy_id)
      |> dict.to_list()
  let license_deadline = utils.bytearray_to_int(license_asset_name)
  let Interval {
    lower_bound: IntervalBound { bound_type: lower_bound_type, .. },
    upper_bound: IntervalBound { bound_type: upper_bound_type, .. },
  } = validity_range
  expect Finite(start_valid_time_range) = lower_bound_type
  expect Finite(end_valid_time_range) = upper_bound_type
  // - Only Batcher with valid license token can trigger @ApplyPool redeemer validation.  
  // - A valid license token is the token with @tokenName (representing for expired milliseconds) 
  //   and must be within the time range from current_time to current_time + maximum_deadline_range
  and {
    license_amount == 1,
    license_deadline >= end_valid_time_range,
    license_deadline <= start_valid_time_range + maximum_deadline_range,
  }
}
