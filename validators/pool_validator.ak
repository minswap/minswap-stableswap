use aiken/dict.{Dict}
use aiken/hash.{Blake2b_256, Hash}
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, ScriptContext, Spend,
  Transaction, ValidityRange,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{PolicyId, Value}
use stableswap/pool_utils as poolutils
use stableswap/types.{
  ApplyPool, Asset, Deposit, Exchange, OrderDatum, PoolDatum, PoolParams,
  PoolRedeemer, UpdateAmpOrStakeCredential, Withdraw, WithdrawAdminFee,
  WithdrawImbalance, WithdrawOneCoin,
}
use stableswap/utils

validator(params: PoolParams) {
  fn validate_pool(
    datum: PoolDatum,
    redeemer: PoolRedeemer,
    context: ScriptContext,
  ) -> Bool {
    let ScriptContext { transaction, purpose } = context
    let Transaction { inputs, .. } = transaction
    expect Spend(pool_ref) = purpose
    expect Some(pool_input) = transaction.find_input(inputs, pool_ref)
    when redeemer is {
      ApplyPool(batcher_address, input_indexes, license_idx) ->
        validate_apply_pool(
          params: params,
          transaction: transaction,
          pool_input: pool_input,
          pool_in_datum: datum,
          batcher_address: batcher_address,
          input_indexes: input_indexes,
          license_idx: license_idx,
        )
      WithdrawAdminFee(admin_index, fee_to_index) ->
        validate_withdraw_admin_fee(
          params: params,
          transaction: transaction,
          pool_input: pool_input,
          pool_in_datum: datum,
          admin_index: admin_index,
          fee_to_index: fee_to_index,
        )
      UpdateAmpOrStakeCredential(admin_index) ->
        validate_update_amp_or_update_stake_credential(
          params: params,
          transaction: transaction,
          pool_input: pool_input,
          pool_in_datum: datum,
          admin_index: admin_index,
        )
    }
  }
}

// This function will trigger validation of ApplyPool redeemer
fn validate_apply_pool(
  params: PoolParams,
  transaction: Transaction,
  pool_input: Input,
  pool_in_datum: PoolDatum,
  batcher_address: Address,
  input_indexes: List<Int>,
  license_idx: Int,
) -> Bool {
  let Transaction {
    inputs,
    outputs,
    mint,
    validity_range,
    extra_signatories,
    datums,
    ..
  } = transaction
  let PoolParams {
    nft_asset,
    lp_asset,
    assets,
    multiples,
    fee,
    admin_fee,
    fee_denominator,
    license_symbol,
    maximum_deadline_range,
    ..
  } = params
  let Input { output: pool_in_output, .. } = pool_input
  let Output { address: pool_in_address, value: pool_in_value, .. } =
    pool_in_output
  let Address { payment_credential: pool_in_address_payment_credential, .. } =
    pool_in_address

  // - The validation requires having only a single Pool Input and a Pool Output in single batching transaction
  // - The Pool Input and Output must have the same Address (both payment and stake credential part)
  // - The idea here is that we will find the output having the same address with the spending input and 
  //   make sure that there's only one input and one output matching with pool's payment_credential
  expect [pool_output] =
    list.filter(
      outputs,
      fn(o) {
        let Output { address: addr, .. } = o
        addr == pool_in_address
      },
    )
  let Output { value: pool_out_value, .. } = pool_output

  // Batching transaction only allow 1 Pool UTxO in the Inputs
  expect [_] =
    list.filter(
      inputs,
      fn(i) {
        let Input { output: out, .. } = i
        let Output { address: addr, .. } = out
        let Address { payment_credential, .. } = addr
        payment_credential == pool_in_address_payment_credential
      },
    )

  expect pool_out_datum: PoolDatum =
    must_find_script_datum(outputs, datums, pool_output)
  let PoolDatum {
    balances: pool_out_balances,
    total_liquidity: pool_out_total_liquidity,
    amp: pool_out_amp,
    order_hash: pool_out_order_hash,
  } = pool_out_datum

  let PoolDatum {
    balances: pool_in_balances,
    total_liquidity: pool_in_total_liquidity,
    amp: pool_in_amp,
    order_hash: pool_in_order_hash,
  } = pool_in_datum

  // - Pool NFT is the part of Pool Value, which is known as Pool Identifier
  // - Pool NFT must be existed on both Pool In/Output Value
  let Asset { policy_id: nft_policy_id, asset_name: nft_asset_name } = nft_asset

  // Pool NFT must be existed in Pool Input and Output value
  expect value.quantity_of(pool_in_value, nft_policy_id, nft_asset_name) == 1
  expect value.quantity_of(pool_out_value, nft_policy_id, nft_asset_name) == 1
  // Pool Value must only contains necessary token inside
  expect check_pool_value(pool_out_value, assets)
  // In @ApplyPool Redeemer, only balances and total_liquidity can be changed.
  // The Amplification Coeffience & Order Hash must be unchanged. Amplification Coeffience can only be update via @UpdateAmp redeemer
  expect
    pool_in_amp == pool_out_amp && pool_in_order_hash == pool_out_order_hash
  let license_input = utils.list_at_index(inputs, license_idx)
  let license_deadline =
    find_license_deadline(license_symbol, license_input.output.value)
  let (start_valid_time_range, end_valid_time_range) =
    find_posix_time_range(validity_range)

  // - Only Batcher with valid license token can trigger @ApplyPool redeemer validation.  
  // - A valid license token is the token with @tokenName (representing for expired milliseconds) 
  //   and must be within the time range from current_time to current_time + maximum_deadline_range
  let Address { payment_credential: batcher_payment_credential, .. } =
    batcher_address
  expect VerificationKeyCredential(batcher_pkh) = batcher_payment_credential
  // Batcher with valid license token must be a signer of transaction
  expect
    list.has(extra_signatories, batcher_pkh) && license_deadline >= end_valid_time_range && license_deadline <= start_valid_time_range + maximum_deadline_range
  let user_inputs =
    list.filter(
      inputs,
      fn(input) {
        let Input { output: out, .. } = input
        let Output { address: addr, .. } = out
        let Address { payment_credential: payment_cred, .. } = addr
        when payment_cred is {
          ScriptCredential(hash) -> hash == pool_in_order_hash
          _ -> False
        }
      },
    )
  let unique_input_indexes = list.unique(input_indexes)

  // Currently, transaction inputs will be sorted by TxId and TxIndex of UTxO.
  // We have to calculate indexes of orders inputs sorting by the ASC created time
  // on the off-chain and on-chain will sort the TxIns by the indexes
  // Input Indexes in parameter will be reversed indexs of @user_inputs to reduce calculate step in On-Chain
  let sorted_users_inputs =
    list.foldl(
      unique_input_indexes,
      [],
      fn(idx, ips) { list.push(ips, utils.list_at_index(user_inputs, idx)) },
    )
  let user_outputs =
    list.filter(
      outputs,
      fn(output) {
        let Output { address: addr, .. } = output
        addr != pool_in_address && addr != batcher_address
      },
    )
  expect
    unique_input_indexes == input_indexes && // @input_indexes which is provided by Batcher must be unique array
    list.length(user_inputs) == list.length(unique_input_indexes) && // @input_indexes and @user_inputs must have the same length
    // User Inputs and Outputs must have the same length
    list.length(sorted_users_inputs) == list.length(user_outputs)

  let value_balances_in =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(pool_in_value, policy_id, asset_name)
      },
    )
  let value_balances_out =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(pool_out_value, policy_id, asset_name)
      },
    )
  let assets_length = list.length(assets)
  // Balances list in Pool In/Out datum must have the same length with Pool Assets list
  expect
    assets_length == list.length(pool_in_balances) && assets_length == list.length(
      pool_out_balances,
    )
  let (new_datum_balances, new_value_balances, new_total_liquidity) =
    apply_orders(
      all_outputs: outputs,
      datum_dict: datums,
      user_inputs: sorted_users_inputs,
      user_outputs: user_outputs,
      assets: assets,
      multiples: multiples,
      lp_asset: lp_asset,
      amp: pool_in_amp,
      fee: fee,
      admin_fee: admin_fee,
      fee_denominator: fee_denominator,
      pool_state: (pool_in_balances, value_balances_in, pool_in_total_liquidity),
    )

  // Validate the Pool State (datum balances, value balances and total_liquidity) must be the same with the calculated amount after applying through all orders
  expect
    value_balances_out == new_value_balances && pool_out_balances == new_datum_balances && pool_out_total_liquidity == new_total_liquidity
  let mint_value = value.from_minted_value(mint)
  let mint_length = list.length(value.flatten(mint_value))
  let total_delta_liquidity = pool_out_total_liquidity - pool_in_total_liquidity
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset

  // Validate that @mint can only contains LP Token if having any order requires minting LP, otherwise, it must be empty
  expect
    if total_delta_liquidity != 0 {
      mint_length == 1
    } else {
      mint_length == 0
    }
  expect
    value.quantity_of(mint_value, lp_policy_id, lp_asset_name) == total_delta_liquidity
  True
}

// This function will trigger validation of WithdrawAdminFee redeemer
fn validate_withdraw_admin_fee(
  params: PoolParams,
  transaction: Transaction,
  pool_input: Input,
  pool_in_datum: PoolDatum,
  admin_index: Int,
  fee_to_index: Int,
) -> Bool {
  let Transaction { inputs, outputs, mint, datums, redeemers, .. } = transaction
  let PoolParams { nft_asset, assets, admin_asset, .. } = params
  let Input { output: pool_in_output, .. } = pool_input
  let Output { address: pool_in_address, value: pool_in_value, .. } =
    pool_in_output

  // - The validation requires having only a single Pool Output
  // - The Pool Input and Output must have the same Address (both payment and stake credential part)
  expect [pool_output] =
    list.filter(outputs, fn(o) { o.address == pool_in_address })
  let Output { value: pool_out_value, .. } = pool_output

  // Having only one Pool Input in the transaction and make sure that it's an unique script in the input.
  expect dict.size(redeemers) == 1
  expect pool_out_datum: PoolDatum =
    must_find_script_datum(outputs, datums, pool_output)

  let PoolDatum { balances: pool_in_balances, .. } = pool_in_datum

  // - Pool NFT is the part of Pool Value, which is known as Pool Identifier
  // - Pool NFT must be existed on both Pool In/Output Value
  let Asset { policy_id: nft_policy_id, asset_name: nft_asset_name } = nft_asset

  // Pool NFT must be existed in Pool Input and Output value
  expect value.quantity_of(pool_in_value, nft_policy_id, nft_asset_name) == 1
  expect value.quantity_of(pool_out_value, nft_policy_id, nft_asset_name) == 1
  // Pool Value must only contains necessary token inside
  expect check_pool_value(pool_out_value, assets)
  // Pool Datum must be unchanged in this redeemer
  expect pool_in_datum == pool_out_datum
  let value_balances_in =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(pool_in_value, policy_id, asset_name)
      },
    )
  let value_balances_out =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(pool_out_value, policy_id, asset_name)
      },
    )
  // After Admin Fee amounts are withdrawn, Pool Value must be equals with Datum balances
  expect value_balances_out == pool_in_balances
  // - Admin Fee amounts are the amounts belonged to Admin 
  // - These amounts are accumulated in Pool Value and 
  //   are calculated by the diff of Pool Value and Datum Balances 
  let admin_fee_amounts =
    utils.zip_with(
      value_balances_in,
      pool_in_balances,
      fn(val, bal) { val - bal },
    )
  let fee_to_output = utils.list_at_index(outputs, fee_to_index)
  let withdrawal_amounts =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(fee_to_output.value, policy_id, asset_name)
      },
    )
  // Admin can only withdraw the exact accumulated admin fee amounts
  expect withdrawal_amounts == admin_fee_amounts
  let admin_input = utils.list_at_index(inputs, admin_index)
  let admin_value = admin_input.output.value
  let Asset { policy_id: admin_policy_id, asset_name: admin_asset_name } =
    admin_asset

  // Only Admin token can trigger this redeemer
  expect value.quantity_of(admin_value, admin_policy_id, admin_asset_name) == 1
  let mint_value = value.from_minted_value(mint)
  // This Redeemer won't mint anything 
  expect [] = value.flatten(mint_value)

  True
}

// This function will trigger validation of UpdateAmpOrStakeCredential redeemer
fn validate_update_amp_or_update_stake_credential(
  params: PoolParams,
  transaction: Transaction,
  pool_input: Input,
  pool_in_datum: PoolDatum,
  admin_index: Int,
) -> Bool {
  let Transaction { inputs, outputs, mint, datums, redeemers, .. } = transaction
  let PoolParams { nft_asset, assets, admin_asset, .. } = params
  let Input { output: pool_in_output, .. } = pool_input
  let Output { address: pool_in_address, value: pool_in_value, .. } =
    pool_in_output
  let Address { payment_credential: pool_in_address_payment_credential, .. } =
    pool_in_address

  // - The validation requires having only a single Pool Output
  // - The Pool Input and Output must have the same Address (only payment_credential part)
  // - Admin can do either update AMP or update stake_credential in this redeemer
  // - We also make sure that there's only one output matching with pool's payment_credential
  expect [pool_output] =
    list.filter(
      outputs,
      fn(o) {
        let Output { address: addr, .. } = o
        let Address { payment_credential, .. } = addr
        payment_credential == pool_in_address_payment_credential
      },
    )
  let Output { value: pool_out_value, .. } = pool_output

  // Having only one Pool Input in the transaction and make sure that it's an unique script in the input.
  expect dict.size(redeemers) == 1
  expect pool_out_datum: PoolDatum =
    must_find_script_datum(outputs, datums, pool_output)

  let PoolDatum {
    balances: pool_out_balances,
    total_liquidity: pool_out_total_liquidity,
    order_hash: pool_out_order_hash,
    ..
  } = pool_out_datum

  let PoolDatum {
    balances: pool_in_balances,
    total_liquidity: pool_in_total_liquidity,
    order_hash: pool_in_order_hash,
    ..
  } = pool_in_datum

  // - Pool NFT is the part of Pool Value, which is known as Pool Identifier
  // - Pool NFT must be existed on both Pool In/Output Value
  let Asset { policy_id: nft_policy_id, asset_name: nft_asset_name } = nft_asset
  // Pool NFT must be existed in Pool Input and Output value
  expect value.quantity_of(pool_in_value, nft_policy_id, nft_asset_name) == 1
  expect value.quantity_of(pool_out_value, nft_policy_id, nft_asset_name) == 1
  // Pool Value must only contains necessary token inside
  expect check_pool_value(pool_out_value, assets)
  // - Only Pool Datum's AMP can be updated, other fields must remain unchanged
  // - TODO: Research the acceptable range which AMP can be changed
  expect
    pool_in_balances == pool_out_balances && pool_in_total_liquidity == pool_out_total_liquidity && pool_in_order_hash == pool_out_order_hash
  let value_balances_in =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(pool_in_value, policy_id, asset_name)
      },
    )
  let value_balances_out =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(pool_out_value, policy_id, asset_name)
      },
    )
  // Pool Value must be unchanged in this redeemer
  expect value_balances_in == value_balances_out
  let admin_input = utils.list_at_index(inputs, admin_index)
  let admin_value = admin_input.output.value
  let Asset { policy_id: admin_policy_id, asset_name: admin_asset_name } =
    admin_asset
  // Only Admin token can trigger this redeemer
  expect value.quantity_of(admin_value, admin_policy_id, admin_asset_name) == 1
  let mint_value = value.from_minted_value(mint)
  // This Redeemer won't mint anything 
  expect [] = value.flatten(mint_value)

  True
}

fn find_order_datum(
  outputs: List<Output>,
  datums: Dict<Hash<Blake2b_256, Data>, Data>,
  output: Output,
) -> OrderDatum {
  expect order_datum: OrderDatum =
    must_find_script_datum(outputs, datums, output)
  order_datum
}

fn apply_orders(
  all_outputs: List<Output>,
  datum_dict: Dict<Hash<Blake2b_256, Data>, Data>,
  user_inputs: List<Input>,
  user_outputs: List<Output>,
  assets: List<Asset>,
  multiples: List<Int>,
  lp_asset: Asset,
  amp: Int,
  fee: Int,
  admin_fee: Int,
  fee_denominator: Int,
  pool_state: (List<Int>, List<Int>, Int),
) -> (List<Int>, List<Int>, Int) {
  when user_inputs is {
    [] -> pool_state
    [input, ..inputs] ->
      when user_outputs is {
        [] -> pool_state
        [output, ..outputs] -> {
          let Input { output: order_in_output, .. } = input
          let Output { value: order_in_value, .. } = order_in_output
          let Output {
            value: order_out_value,
            address: output_address,
            datum: order_output_datum,
            ..
          } = output
          let OrderDatum {
            receiver,
            batcher_fee,
            output_ada,
            step: order_step,
            receiver_datum_hash,
            ..
          } = find_order_datum(all_outputs, datum_dict, order_in_output)
          let is_valid_receiver_datum_hash =
            when receiver_datum_hash is {
              Some(datum_hash) -> {
                expect DatumHash(output_datum_hash) = order_output_datum
                output_datum_hash == datum_hash
              }
              None -> order_output_datum == NoDatum
            }
          // Verify Order Datum is correct
          expect
            receiver == output_address && batcher_fee > 0 && output_ada > 0 && is_valid_receiver_datum_hash
          let new_state =
            when order_step is {
              Exchange(asset_in_index, asset_out_index, minimum_asset_out) -> {
                expect minimum_asset_out > 0
                validate_exchange(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  in_index: asset_in_index,
                  out_index: asset_out_index,
                  minimum_amount_out: minimum_asset_out,
                  output_ada: output_ada,
                  assets: assets,
                  multiples: multiples,
                  amp: amp,
                  fee: fee,
                  admin_fee: admin_fee,
                  fee_denominator: fee_denominator,
                  pool_state: pool_state,
                )
              }
              Deposit(minimum_lp) -> {
                expect minimum_lp > 0
                validate_deposit(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_lp: minimum_lp,
                  output_ada: output_ada,
                  assets: assets,
                  multiples: multiples,
                  lp_asset: lp_asset,
                  amp: amp,
                  fee: fee,
                  admin_fee: admin_fee,
                  fee_denominator: fee_denominator,
                  pool_state: pool_state,
                )
              }
              Withdraw(minimum_amounts) -> {
                expect utils.verify_non_negative_amounts(minimum_amounts)
                validate_withdraw(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  minimum_amounts: minimum_amounts,
                  output_ada: output_ada,
                  assets: assets,
                  lp_asset: lp_asset,
                  pool_state: pool_state,
                )
              }
              WithdrawImbalance(amounts_out) -> {
                expect utils.verify_non_negative_amounts(amounts_out)
                validate_withdraw_imbalance(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  amounts_out: amounts_out,
                  output_ada: output_ada,
                  assets: assets,
                  multiples: multiples,
                  lp_asset: lp_asset,
                  amp: amp,
                  fee: fee,
                  admin_fee: admin_fee,
                  fee_denominator: fee_denominator,
                  pool_state: pool_state,
                )
              }
              WithdrawOneCoin(asset_out_index, minimum_asset_out) -> {
                expect minimum_asset_out > 0
                validate_withdraw_one_coin(
                  order_in_value: order_in_value,
                  order_out_value: order_out_value,
                  out_index: asset_out_index,
                  minimum_amount_out: minimum_asset_out,
                  output_ada: output_ada,
                  assets: assets,
                  multiples: multiples,
                  lp_asset: lp_asset,
                  amp: amp,
                  fee: fee,
                  admin_fee: admin_fee,
                  fee_denominator: fee_denominator,
                  pool_state: pool_state,
                )
              }
            }
          apply_orders(
            all_outputs: all_outputs,
            datum_dict: datum_dict,
            user_inputs: inputs,
            user_outputs: outputs,
            assets: assets,
            multiples: multiples,
            lp_asset: lp_asset,
            amp: amp,
            fee: fee,
            admin_fee: admin_fee,
            fee_denominator: fee_denominator,
            pool_state: new_state,
          )
        }
      }
  }
}

fn calculate_deposit(
  multiples: List<Int>,
  fee: Int,
  admin_fee: Int,
  fee_denominator: Int,
  assets: List<Asset>,
  amount_ins: List<Int>,
  amp: Int,
  datum_balances: List<Int>,
  value_balances: List<Int>,
  total_liquidity: Int,
) -> (List<Int>, List<Int>, Int) {
  let new_value_balances =
    utils.zip_with(value_balances, amount_ins, fn(balance, in) { balance + in })
  if total_liquidity == 0 {
    expect utils.verify_positive_ints(amount_ins)
    let new_datum_balances =
      utils.zip_with(
        datum_balances,
        amount_ins,
        fn(balance, in) { balance + in },
      )
    let d1 = poolutils.get_d_mem(new_datum_balances, multiples, amp)
    expect d1 > 0
    (new_datum_balances, new_value_balances, d1)
  } else {
    let new_datum_balances_without_fee =
      utils.zip_with(
        datum_balances,
        amount_ins,
        fn(balance, in) { balance + in },
      )
    let d0 = poolutils.get_d_mem(datum_balances, multiples, amp)
    let d1 = poolutils.get_d_mem(new_datum_balances_without_fee, multiples, amp)
    let asset_length = list.length(assets)
    let special_fee = fee * asset_length / ( 4 * ( asset_length - 1 ) )
    let new_datum_balances_pair: List<(Int, Int)> =
      utils.zip_with(
        datum_balances,
        new_datum_balances_without_fee,
        fn(old_balance, new_balance) {
          let ideal_balance = d1 * old_balance / d0
          let difference = utils.abs(new_balance - ideal_balance)
          let trading_fee_amount = special_fee * difference / fee_denominator
          let admin_fee_amount =
            trading_fee_amount * admin_fee / fee_denominator
          (new_balance - admin_fee_amount, new_balance - trading_fee_amount)
        },
      )
    let new_datum_balances =
      list.map(
        new_datum_balances_pair,
        fn(pair) {
          let (fst, _) = pair
          fst
        },
      )
    let new_datum_balances_with_trading_fee =
      list.map(
        new_datum_balances_pair,
        fn(pair) {
          let (_, snd) = pair
          snd
        },
      )
    expect utils.verify_positive_ints(new_datum_balances_with_trading_fee)
    let d2 =
      poolutils.get_d_mem(new_datum_balances_with_trading_fee, multiples, amp)
    let lp_amount = total_liquidity * ( d2 - d0 ) / d0
    expect d1 > d0
    (new_datum_balances, new_value_balances, lp_amount)
  }
}

fn validate_deposit(
  order_in_value: Value,
  order_out_value: Value,
  minimum_lp: Int,
  output_ada: Int,
  assets: List<Asset>,
  multiples: List<Int>,
  lp_asset: Asset,
  amp: Int,
  fee: Int,
  admin_fee: Int,
  fee_denominator: Int,
  pool_state: (List<Int>, List<Int>, Int),
) -> (List<Int>, List<Int>, Int) {
  let (datum_balances, value_balances, total_liquidity) = pool_state
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset
  let amount_ins =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(order_in_value, policy_id, asset_name)
      },
    )
  let (new_datum_balances, new_value_balances, lp_amount) =
    calculate_deposit(
      multiples: multiples,
      fee: fee,
      admin_fee: admin_fee,
      fee_denominator: fee_denominator,
      assets: assets,
      amount_ins: amount_ins,
      amp: amp,
      datum_balances: datum_balances,
      value_balances: value_balances,
      total_liquidity: total_liquidity,
    )
  let amount_lp_out =
    value.quantity_of(order_out_value, lp_policy_id, lp_asset_name)
  let amount_ada_out =
    value.quantity_of(
      order_out_value,
      value.ada_policy_id,
      value.ada_asset_name,
    )
  // Make sure that the actual lp amount will be minted must be greater than the minimum acceptance of this order
  expect lp_amount >= minimum_lp
  // Verify the amount will be returned to users must be followed by the calculation above
  expect lp_amount == amount_lp_out && amount_ada_out == output_ada
  // Verify the output will be returned to users must contains only necessary tokens
  expect list.length(value.flatten(order_out_value)) == 2
  (new_datum_balances, new_value_balances, total_liquidity + lp_amount)
}

fn validate_withdraw(
  order_in_value: Value,
  order_out_value: Value,
  minimum_amounts: List<Int>,
  output_ada: Int,
  assets: List<Asset>,
  lp_asset: Asset,
  pool_state: (List<Int>, List<Int>, Int),
) -> (List<Int>, List<Int>, Int) {
  let (datum_balances, value_balances, total_liquidity) = pool_state
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset
  let withdrawal_lp_amount =
    value.quantity_of(order_in_value, lp_policy_id, lp_asset_name)
  let asset_amounts =
    list.map(
      datum_balances,
      fn(balance) { balance * withdrawal_lp_amount / total_liquidity },
    )
  let new_datum_balances =
    utils.zip_with(datum_balances, asset_amounts, fn(b1, b2) { b1 - b2 })
  let new_value_balances =
    utils.zip_with(value_balances, asset_amounts, fn(b1, b2) { b1 - b2 })
  // Make sure that the actual assets amount must be greater than the minimum acceptance of this order
  expect
    utils.compare_list_with(
      asset_amounts,
      minimum_amounts,
      fn(actual, expt) { actual >= expt },
    )
  let assets_amount_out =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(order_out_value, policy_id, asset_name)
      },
    )
  let amount_ada_out =
    value.quantity_of(
      order_out_value,
      value.ada_policy_id,
      value.ada_asset_name,
    )
  // Verify the amount will be returned to users must be followed by the calculation above
  expect assets_amount_out == asset_amounts && amount_ada_out == output_ada
  let stable_assets_in_output_length =
    list.reduce(
      assets_amount_out,
      0,
      fn(n, am) {
        if am > 0 {
          n + 1
        } else {
          n
        }
      },
    )
  let expected_value_out_length = stable_assets_in_output_length + 1
  // Verify the output will be returned to users must contains only necessary tokens
  expect
    list.length(value.flatten(order_out_value)) == expected_value_out_length
  (
    new_datum_balances,
    new_value_balances,
    total_liquidity - withdrawal_lp_amount,
  )
}

fn calculate_exchange(
  multiples: List<Int>,
  fee: Int,
  admin_fee: Int,
  fee_denominator: Int,
  amount_in: Int,
  in_index: Int,
  out_index: Int,
  amp: Int,
  datum_balances: List<Int>,
  value_balances: List<Int>,
) -> (Int, List<Int>, List<Int>) {
  let multiple_balances =
    utils.zip_with(
      datum_balances,
      multiples,
      fn(balance, multiple) { balance * multiple },
    )
  let multiple_in = utils.list_at_index(multiples, in_index)
  let multiple_out = utils.list_at_index(multiples, out_index)
  let multiple_balances_in = utils.list_at_index(multiple_balances, in_index)
  let multiple_balances_out = utils.list_at_index(multiple_balances, out_index)
  let x = multiple_balances_in + amount_in * multiple_in
  let y = poolutils.get_y(in_index, out_index, x, multiple_balances, amp)
  let dy = multiple_balances_out - y
  let dy_fee = dy * fee / fee_denominator
  let dy_admin_fee = dy_fee * admin_fee / fee_denominator
  let amount_out = ( dy - dy_fee ) / multiple_out
  let new_datum_balance_in = x / multiple_in
  let new_datum_balance_out = ( y + ( dy_fee - dy_admin_fee ) ) / multiple_out
  let new_datum_balances =
    list.indexed_map(
      datum_balances,
      fn(idx, balance) {
        if idx == in_index {
          new_datum_balance_in
        } else if idx == out_index {
          new_datum_balance_out
        } else {
          balance
        }
      },
    )
  let new_value_balances =
    list.indexed_map(
      value_balances,
      fn(idx, balance) {
        if idx == in_index {
          balance + amount_in
        } else if idx == out_index {
          balance - amount_out
        } else {
          balance
        }
      },
    )
  (amount_out, new_datum_balances, new_value_balances)
}

fn validate_exchange(
  order_in_value: Value,
  order_out_value: Value,
  in_index: Int,
  out_index: Int,
  minimum_amount_out: Int,
  output_ada: Int,
  assets: List<Asset>,
  multiples: List<Int>,
  amp: Int,
  fee: Int,
  admin_fee: Int,
  fee_denominator: Int,
  pool_state: (List<Int>, List<Int>, Int),
) -> (List<Int>, List<Int>, Int) {
  let (datum_balances, value_balances, total_liquidity) = pool_state
  let Asset { policy_id: asset_in_policy_id, asset_name: asset_in_asset_name } =
    utils.list_at_index(assets, in_index)
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    utils.list_at_index(assets, out_index)
  let amount_in =
    value.quantity_of(order_in_value, asset_in_policy_id, asset_in_asset_name)
  let (amount_out, new_datum_balances, new_value_balances) =
    calculate_exchange(
      multiples: multiples,
      fee: fee,
      admin_fee: admin_fee,
      fee_denominator: fee_denominator,
      amount_in: amount_in,
      in_index: in_index,
      out_index: out_index,
      amp: amp,
      datum_balances: datum_balances,
      value_balances: value_balances,
    )
  // Make sure that the actual asset amount must be greater than the minimum acceptance of this order
  expect amount_out >= minimum_amount_out
  let asset_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let amount_ada_out =
    value.quantity_of(
      order_out_value,
      value.ada_policy_id,
      value.ada_asset_name,
    )
  // Verify the amount will be returned to users must be followed by the calculation above
  expect asset_amount_out == amount_out && amount_ada_out == output_ada
  // Verify the output will be returned to users must contains only necessary tokens
  expect list.length(value.flatten(order_out_value)) == 2
  (new_datum_balances, new_value_balances, total_liquidity)
}

fn validate_withdraw_imbalance(
  order_in_value: Value,
  order_out_value: Value,
  amounts_out: List<Int>,
  output_ada: Int,
  assets: List<Asset>,
  multiples: List<Int>,
  lp_asset: Asset,
  amp: Int,
  fee: Int,
  admin_fee: Int,
  fee_denominator: Int,
  pool_state: (List<Int>, List<Int>, Int),
) -> (List<Int>, List<Int>, Int) {
  let (datum_balances, value_balances, total_liquidity) = pool_state
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset
  let new_datum_balances_without_fee =
    utils.zip_with(
      datum_balances,
      amounts_out,
      fn(balance, out) { balance - out },
    )
  expect utils.verify_positive_ints(new_datum_balances_without_fee)
  let n = list.length(datum_balances)
  let d0 = poolutils.get_d_mem(datum_balances, multiples, amp)
  let d1 = poolutils.get_d_mem(new_datum_balances_without_fee, multiples, amp)
  let special_fee = fee * n / ( 4 * ( n - 1 ) )
  let new_datum_balances_pair =
    utils.zip_with(
      datum_balances,
      new_datum_balances_without_fee,
      fn(old_balance, new_balance) {
        let ideal_balance = d1 * old_balance / d0
        let difference = utils.abs(new_balance - ideal_balance)
        let trading_fee_amount = special_fee * difference / fee_denominator
        let admin_fee_amount = trading_fee_amount * admin_fee / fee_denominator
        (new_balance - admin_fee_amount, new_balance - trading_fee_amount)
      },
    )
  let new_datum_balances =
    list.map(
      new_datum_balances_pair,
      fn(pair) {
        let (fst, _) = pair
        fst
      },
    )
  let new_datum_balances_with_trading_fee =
    list.map(
      new_datum_balances_pair,
      fn(pair) {
        let (_, snd) = pair
        snd
      },
    )
  expect utils.verify_positive_ints(new_datum_balances_with_trading_fee)
  let d2 =
    poolutils.get_d_mem(new_datum_balances_with_trading_fee, multiples, amp)
  let withdrawal_lp_amount =
    value.quantity_of(order_in_value, lp_policy_id, lp_asset_name)
  let necessary_lp_amount = total_liquidity * ( d0 - d2 ) / d0 + 1

  // Make sure that the nessesary lp amount must be positive and less than the LP of this order
  expect necessary_lp_amount > 1 && withdrawal_lp_amount >= necessary_lp_amount
  let asset_amounts_out =
    list.map(
      assets,
      fn(asset) {
        let Asset { policy_id, asset_name } = asset
        value.quantity_of(order_out_value, policy_id, asset_name)
      },
    )
  let amount_ada_out =
    value.quantity_of(
      order_out_value,
      value.ada_policy_id,
      value.ada_asset_name,
    )
  let change_lp_amount =
    value.quantity_of(order_out_value, lp_policy_id, lp_asset_name)

  // Verify the amount will be returned to users must be followed by the calculation above
  expect
    amounts_out == asset_amounts_out && amount_ada_out == output_ada && change_lp_amount == withdrawal_lp_amount - necessary_lp_amount
  let new_value_balances =
    utils.zip_with(
      value_balances,
      amounts_out,
      fn(balance, out) { balance - out },
    )
  let stable_assets_in_output_length =
    list.reduce(
      asset_amounts_out,
      0,
      fn(n, am) {
        if am > 0 {
          n + 1
        } else {
          n
        }
      },
    )
  let expected_value_out_length =
    if change_lp_amount > 0 {
      stable_assets_in_output_length + 2
    } else {
      stable_assets_in_output_length + 1
    }

  // Verify the output will be returned to users must contains only necessary tokens
  expect
    list.length(value.flatten(order_out_value)) == expected_value_out_length
  (
    new_datum_balances,
    new_value_balances,
    total_liquidity - necessary_lp_amount,
  )
}

fn calculate_withdraw_one_coin(
  multiples: List<Int>,
  fee: Int,
  fee_denominator: Int,
  amount_lp_in: Int,
  out_index: Int,
  amp: Int,
  datum_balances: List<Int>,
  total_liquidity: Int,
) -> (Int, Int) {
  let multiple_balances =
    utils.zip_with(
      datum_balances,
      multiples,
      fn(balance, multiple) { balance * multiple },
    )
  let d0 = poolutils.get_d(multiple_balances, amp)
  let d1 = d0 - amount_lp_in * d0 / total_liquidity
  let new_y = poolutils.get_y_d(out_index, multiple_balances, amp, d1)
  let multiple_out = utils.list_at_index(multiples, out_index)
  let out_amount_without_fee =
    ( utils.list_at_index(multiple_balances, out_index) - new_y ) / multiple_out
  let assets_length = list.length(datum_balances)
  let special_fee = fee * assets_length / ( 4 * ( assets_length - 1 ) )
  let multiple_balances_reduced =
    list.indexed_map(
      multiple_balances,
      fn(idx, old_bal) {
        let diff =
          if idx == out_index {
            old_bal * d1 / d0 - new_y
          } else {
            old_bal - old_bal * d1 / d0
          }
        old_bal - special_fee * diff / fee_denominator
      },
    )
  let out_amount =
    (
      utils.list_at_index(multiple_balances_reduced, out_index) - poolutils.get_y_d(
        out_index,
        multiple_balances_reduced,
        amp,
        d1,
      ) - 1
    ) / multiple_out
  (out_amount, out_amount_without_fee - out_amount)
}

fn validate_withdraw_one_coin(
  order_in_value: Value,
  order_out_value: Value,
  out_index: Int,
  minimum_amount_out: Int,
  output_ada: Int,
  assets: List<Asset>,
  multiples: List<Int>,
  lp_asset: Asset,
  amp: Int,
  fee: Int,
  admin_fee: Int,
  fee_denominator: Int,
  pool_state: (List<Int>, List<Int>, Int),
) -> (List<Int>, List<Int>, Int) {
  let (datum_balances, value_balances, total_liquidity) = pool_state
  let asset_out = utils.list_at_index(assets, out_index)
  let Asset { policy_id: lp_policy_id, asset_name: lp_asset_name } = lp_asset
  let amount_lp_in =
    value.quantity_of(order_in_value, lp_policy_id, lp_asset_name)
  let (amount_out, fee_amount) =
    calculate_withdraw_one_coin(
      multiples: multiples,
      fee: fee,
      fee_denominator: fee_denominator,
      amount_lp_in: amount_lp_in,
      out_index: out_index,
      amp: amp,
      datum_balances: datum_balances,
      total_liquidity: total_liquidity,
    )
  // Make sure that the actual asset amount must be greater than the minimum acceptance of this order
  expect amount_out >= minimum_amount_out
  let Asset { policy_id: asset_out_policy_id, asset_name: asset_out_asset_name } =
    asset_out
  let asset_amount_out =
    value.quantity_of(
      order_out_value,
      asset_out_policy_id,
      asset_out_asset_name,
    )
  let amount_ada_out =
    value.quantity_of(
      order_out_value,
      value.ada_policy_id,
      value.ada_asset_name,
    )
  // Verify the amount will be returned to users must be followed by the calculation above
  expect asset_amount_out == amount_out && amount_ada_out == output_ada
  let admin_fee_amount = fee_amount * admin_fee / fee_denominator
  let new_datum_balances =
    list.indexed_map(
      datum_balances,
      fn(idx, old_bal) {
        if idx == out_index {
          old_bal - amount_out - admin_fee_amount
        } else {
          old_bal
        }
      },
    )
  let new_value_balances =
    list.indexed_map(
      value_balances,
      fn(idx, old_bal) {
        if idx == out_index {
          old_bal - amount_out
        } else {
          old_bal
        }
      },
    )
  // Verify the output will be returned to users must contains only necessary tokens
  expect list.length(value.flatten(order_out_value)) == 2
  (new_datum_balances, new_value_balances, total_liquidity - amount_lp_in)
}

fn find_posix_time_range(time_rage: ValidityRange) -> (Int, Int) {
  expect Finite(t1) = time_rage.lower_bound.bound_type
  expect Finite(t2) = time_rage.upper_bound.bound_type
  (t1, t2)
}

// This function will verify Pool Value elements
// Pool Value only includes minimum ADA, Pool NFT and Stable Assets (if have) 
fn check_pool_value(val: Value, assets: List<Asset>) -> Bool {
  let flatten_val = value.flatten(val)
  let stable_asset_num =
    list.reduce(
      assets,
      0,
      fn(n, asset) {
        let Asset { policy_id, asset_name } = asset
        let c =
          if value.quantity_of(val, policy_id, asset_name) > 0 {
            1
          } else {
            0
          }
        n + c
      },
    )
  list.length(flatten_val) == stable_asset_num + 2
}

fn find_license_deadline(license_symbol: PolicyId, val: Value) -> Int {
  expect [(tn, am)] =
    val
      |> value.tokens(license_symbol)
      |> dict.to_list()
  expect am == 1
  utils.bytearray_to_int(tn)
}

fn must_find_script_datum(
  outputs: List<Output>,
  datums: Dict<Hash<Blake2b_256, Data>, Data>,
  output: Output,
) -> Data {
  let data_option =
    when output.datum is {
      NoDatum -> None
      DatumHash(dh) -> transaction.find_datum(outputs, datums, dh)
      InlineDatum(dat) -> Some(dat)
    }
  utils.must_parse_option(data_option)
}
