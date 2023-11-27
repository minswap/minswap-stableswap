use aiken/list
use aiken/transaction.{Input, Output, ScriptContext, Spend, Transaction}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use stableswap/types.{
  ApplyOrder, CancelOrder, OrderDatum, OrderRedeemer, ValidatorHash,
}

validator(pool_validator_hash: ValidatorHash) {
  fn validate_order(
    raw_datum: Data,
    redeemer: OrderRedeemer,
    context: ScriptContext,
  ) -> Bool {
    let ScriptContext { transaction, purpose } = context
    expect Spend(_) = purpose
    when redeemer is {
      ApplyOrder -> {
        let Transaction { inputs, .. } = transaction
        // Verify having only single Pool Input in this transaction
        expect [_] =
          list.filter(
            inputs,
            fn(i) {
              let Input { output, .. } = i
              let Output { address, .. } = output
              let Address { payment_credential, .. } = address
              when payment_credential is {
                ScriptCredential(hash) -> pool_validator_hash == hash
                _ -> False
              }
            },
          )
        True
      }
      CancelOrder -> {
        let Transaction { inputs, extra_signatories, .. } = transaction
        expect order_datum: OrderDatum = raw_datum
        let OrderDatum {
          sender: Address { payment_credential: owner_payment_credential, .. },
          ..
        } = order_datum
        // validate that the transaction has _sender_'s signature or _sender_ script UTxO in the Transaction Inputs
        when owner_payment_credential is {
          VerificationKeyCredential(owner_pkh) ->
            // Verify transaction must be signed by Owner
            list.has(extra_signatories, owner_pkh)
          ScriptCredential(_) ->
            // In case owner is script address, this script will require at least 1 owner UTxO in input
            // If owner UTxO has enough condition to unlock itself, it can unlock this script as well
            list.length(
              list.filter(
                inputs,
                fn(input) {
                  let Input { output, .. } = input
                  let Output { address: out_address, .. } = output
                  let Address { payment_credential: out_payment_credential, .. } =
                    out_address
                  out_payment_credential == owner_payment_credential
                },
              ),
            ) > 0
        }
      }
    }
  }
}
