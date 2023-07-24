use aiken/list
use aiken/transaction.{Input, Mint, Output, ScriptContext, Transaction}
use aiken/transaction/value
use stableswap/types.{Asset}

validator(nft_asset: Asset) {
  fn validate_lp_minting(_redeemer: Data, context: ScriptContext) -> Bool {
    let ScriptContext { transaction, purpose } = context
    expect Mint(own_policy_id) = purpose
    let Transaction { inputs, outputs, mint, .. } = transaction
    let flatten_mint_value = value.flatten(value.from_minted_value(mint))
    let Asset { policy_id: nft_policy_id, asset_name: nft_asset_name } =
      nft_asset

    // Verify there is only single NFT in the Inputs
    expect [_] =
      list.filter(
        inputs,
        fn(i) {
          let Input { output, .. } = i
          let Output { value: v, .. } = output
          value.quantity_of(v, nft_policy_id, nft_asset_name) == 1
        },
      )

    // Verify there is only single NFT in the Outputs
    expect [_] =
      list.filter(
        outputs,
        fn(o) {
          let Output { value: v, .. } = o
          value.quantity_of(v, nft_policy_id, nft_asset_name) == 1
        },
      )

    // Verify only LP Asset is minted in this transaction and its name must be equals NFT name
    expect [(pid, tn, _am)] = flatten_mint_value
    pid == own_policy_id && tn == nft_asset_name
  }
}
