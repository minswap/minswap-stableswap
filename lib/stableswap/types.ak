use aiken/dict.{Dict}
use aiken/hash.{Blake2b_224, Blake2b_256, Hash}
use aiken/transaction/credential.{Address, Script, VerificationKey}
use aiken/transaction/value.{AssetName, PolicyId}

pub type Asset {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type CustomDatumHash =
  Hash<Blake2b_256, Data>

pub type ValidatorHash =
  Hash<Blake2b_224, Script>

pub type PubKeyHash =
  Hash<Blake2b_224, VerificationKey>

pub type DatumMap =
  Dict<Hash<Blake2b_256, Data>, Data>

pub type OrderStep {
  Exchange { asset_in_index: Int, asset_out_index: Int, minimum_asset_out: Int }
  Deposit { minimum_lp: Int }
  Withdraw { minimum_amounts: List<Int> }
  WithdrawImbalance { amounts_out: List<Int> }
  WithdrawOneCoin { asset_out_index: Int, minimum_asset_out: Int }
}

pub type OrderDatum {
  sender: Address,
  receiver: Address,
  receiver_datum_hash: Option<CustomDatumHash>,
  step: OrderStep,
  batcher_fee: Int,
  output_ada: Int,
}

pub type OrderRedeemer {
  ApplyOrder
  CancelOrder
}

pub type PoolDatum {
  balances: List<Int>,
  amp: Int,
  order_hash: ValidatorHash,
}

pub type PoolRedeemer {
  ApplyPool {
    batcher_address: Address,
    input_indexes: List<Int>,
    license_index: Int,
  }
  WithdrawAdminFee { admin_index: Int }
  UpdateAmpOrStakeCredential { admin_index: Int }
}

pub type PoolParams {
  lp_policy_id: PolicyId,
  nft_asset_name: AssetName,
  lp_asset_name: AssetName,
  batcher_license_policy_id: PolicyId,
  admin_asset: Asset,
  maximum_deadline_range: Int,
  assets: List<Asset>,
  multiples: List<Int>,
  fee: Int,
  admin_fee: Int,
  fee_denominator: Int,
}

pub type OrderBatchingRedeemer {
  // it's used for finding Pool Input faster
  pool_input_index: Int,
}
