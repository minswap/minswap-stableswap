use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, ScriptContext, Transaction,
}
use aiken/transaction/value.{AssetName}
use stableswap/types.{Asset, PoolDatum}
use stableswap/utils

validator(
  // @out_ref is a Reference of an Unspent Transaction Output,
  // which will only be spent on `MintFactoryAuthen` redeemer to make sure this redeemer can only be called once
  out_ref: OutputReference,
  // the Pool NFT TokenName
  pool_nft_asset_name: AssetName,
  // the Pool LP TokenName
  pool_lp_asset_name: AssetName,
  // Pool Assets,
  pool_assets: List<Asset>,
) {
  fn validate_lp_minting(_redeemer: Data, context: ScriptContext) -> Bool {
    let ScriptContext { transaction, purpose } = context
    expect Mint(own_policy_id) = purpose
    let Transaction { inputs, outputs, mint, datums, .. } = transaction

    // validate that `out_ref` must be presented in the Transaction Inputs
    expect [_] =
      list.filter(
        inputs,
        fn(input) {
          let Input { output_reference, .. } = input
          output_reference == out_ref
        },
      )

    // validate that there's only single Pool Output that holding Pool NFT Token
    expect [pool_output] =
      list.filter(
        outputs,
        fn(o) {
          let Output { value: v, .. } = o
          value.quantity_of(v, own_policy_id, pool_nft_asset_name) == 1
        },
      )

    let Output { value: pool_value, datum: pool_datum_raw, .. } = pool_output
    expect pool_datum: PoolDatum =
      when pool_datum_raw is {
        InlineDatum(d) -> d
        _ -> utils.must_find_script_datum(datums, pool_datum_raw)
      }

    let PoolDatum { balances: pool_datum_balances, amp: pool_datum_amp, .. } =
      pool_datum
    let expected_pool_datum_without_lovelace =
      value.zero()
        |> value.add(own_policy_id, pool_nft_asset_name, 1)
        |> value.add(own_policy_id, pool_lp_asset_name, utils.max_lp_supply)

    let expected_pool_datum_balances = list.map(pool_assets, fn(_) { 0 })
    let expected_mint =
      value.zero()
        |> value.add(own_policy_id, pool_nft_asset_name, 1)
        |> value.add(own_policy_id, pool_lp_asset_name, utils.max_lp_supply)
    and {
      // Initial Pool Value has only Pool NFT Token and MAX_INT64 LP Token
      expected_pool_datum_without_lovelace == value.without_lovelace(pool_value),
      // Initial AMP factory must be positive
      pool_datum_amp > 0,
      // Initial Pool Balances must be zero array
      expected_pool_datum_balances == pool_datum_balances,
      // Create Pool Transaction must mint only 1 Pool NFT Token and MAX_INT64 LP Token
      expected_mint == value.from_minted_value(mint),
    }
  }
}
