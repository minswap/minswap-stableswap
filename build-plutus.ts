import {
    Lucid,
    MintingPolicy,
    SpendingValidator,
    fromHex,
    C,
    WithdrawalValidator,
    fromText
} from "lucid-cardano";
import * as fs from "fs";

export type StableswapValidators = {
    orderScript: SpendingValidator;
    poolScript: SpendingValidator;
    lpMinting: MintingPolicy;
    orderBatchingScript: WithdrawalValidator;
}

enum NetworkID {
    MAINNET = "mainnet",
    TESTNET = "testnet"
}

type Asset = {
    policyId: string,
    tokenName: string
}

const TESTNET_MAXIMUM_DEADLINE_RANGE = 77760000000n; // 900 days
const TESTNET_FEE = 1000000n
const TESTNET_ADMIN_FEE = 5000000000n
const TESTNET_FEE_DENOMINATOR = 10000000000n
const TESTNET_ASSET_SYMBOL = "e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72"
const TESTNET_POOL_NFT_SYMBOL = "06fe1ba957728130154154d5e5b25a7b533ebe6c4516356c0aa69355"
const TESTNET_LICENSE_SYMBOL = "defbf038da8ec085f9a304f13946f34522c2f7866bac9def8391685b"
const TESTNET_ADMIN_ASSET: Asset = {
    policyId: "defbf038da8ec085f9a304f13946f34522c2f7866bac9def8391685b",
    tokenName: "41444d494e"
}
const TESTNET_STAKE_CREDENTIAL = C.StakeCredential.from_keyhash(C.Ed25519KeyHash.from_hex("83ec96719dc0591034b78e472d6f477446261fec4bc517fa4d047f02"))

const MAINNET_MAXIMUM_DEADLINE_RANGE = 7776000000n; // 90 days
const MAINNET_FEE = 1000000n;
const MAINNET_ADMIN_FEE = 5000000000n;
const MAINNET_FEE_DENOMINATOR = 10000000000n;
const MAINNET_BATCHER_LICENSE_SYMBOL = "53299e1f266eec1030b07866b3c4c4824c8bb4097ccd3d5765204d64";
const MAINNET_ADMIN_ASSET: Asset = {
    policyId: "ef40bdb216a026ef0a72593df1729d368d124e52af655dd452d4631d",
    tokenName: "41444d494e"
}

function bytesFromHex(s: string): Uint8Array {
    if (!/^[a-f0-9]*$/i.test(s)) {
        throw new Error(`invalid hex: ${s}`);
    }
    return Buffer.from(s, "hex");
}

function bytesToHex(bytes: Uint8Array): string {
    return Buffer.from(bytes).toString("hex")
}

function assetToConstr(asset: Asset): C.ConstrPlutusData {
    const li = C.PlutusList.new()
    li.add(C.PlutusData.new_bytes(bytesFromHex(asset.policyId)))
    li.add(C.PlutusData.new_bytes(bytesFromHex(asset.tokenName)))
    const constr = C.ConstrPlutusData.new(C.BigNum.from_str("0"), li)
    return constr
}

function assetToPlutusData(asset: Asset): C.PlutusData {
    return C.PlutusData.new_constr_plutus_data(assetToConstr(asset))
}

type PoolParams = {
    nftAsset: Asset,
    lpAsset: Asset,
    licenseSymbol: string,
    adminAsset: Asset,
    maximumDeadlineRange: bigint,
    assets: Asset[],
    multiples: bigint[],
    fee: bigint,
    adminFee: bigint,
    denominator: bigint,
}

function poolParamsToPlutusData(poolParams: PoolParams): C.PlutusData {
    const li = C.PlutusList.new()
    li.add(assetToPlutusData(poolParams.nftAsset))
    li.add(assetToPlutusData(poolParams.lpAsset))
    li.add(C.PlutusData.new_bytes(bytesFromHex(poolParams.licenseSymbol)))
    li.add(assetToPlutusData(poolParams.adminAsset))
    li.add(C.PlutusData.new_integer(C.BigInt.from_str(poolParams.maximumDeadlineRange.toString())))

    const assetList = C.PlutusList.new()
    for (const as of poolParams.assets) {
        assetList.add(assetToPlutusData(as))
    }
    li.add(C.PlutusData.new_list(assetList))

    const multipleList = C.PlutusList.new()
    for (const m of poolParams.multiples) {
        multipleList.add(C.PlutusData.new_integer(C.BigInt.from_str(m.toString())))
    }
    li.add(C.PlutusData.new_list(multipleList))
    li.add(C.PlutusData.new_integer(C.BigInt.from_str(poolParams.fee.toString())))
    li.add(C.PlutusData.new_integer(C.BigInt.from_str(poolParams.adminFee.toString())))
    li.add(C.PlutusData.new_integer(C.BigInt.from_str(poolParams.denominator.toString())))
    const constr = C.ConstrPlutusData.new(C.BigNum.from_str("0"), li)
    const plutusData = C.PlutusData.new_constr_plutus_data(constr)
    return plutusData
}

function applyDoubleCborEncoding(script: string): string {
    try {
        C.PlutusScript.from_bytes(
            C.PlutusScript.from_bytes(fromHex(script)).bytes(),
        );
        return script;
    } catch (_e) {
        return bytesToHex(C.PlutusScript.new(fromHex(script)).to_bytes());
    }
}

function applyParamsToScript(param: C.PlutusData, script: string) {
    const paramsList = C.PlutusList.new()
    paramsList.add(param)
    const plutusScript = C.apply_params_to_plutus_script(
        paramsList,
        C.PlutusScript.from_bytes(fromHex(applyDoubleCborEncoding(script))),
    )
    return bytesToHex(plutusScript.to_bytes());
}

function buildStakeCredPlutusData(scriptHash: string): C.PlutusData {
    const s1 = C.PlutusList.new()
    s1.add(C.PlutusData.new_bytes(bytesFromHex(scriptHash)))

    const c1 = C.PlutusData.new_constr_plutus_data(
        C.ConstrPlutusData.new(
            C.BigNum.from_str("1"),
            s1
        )
    )

    const s2 = C.PlutusList.new()
    s2.add(c1)

    const c2 = C.PlutusData.new_constr_plutus_data(
        C.ConstrPlutusData.new(
            C.BigNum.from_str("0"),
            s2
        )
    )

    return c2
}

export type PlutusValidatorCompiled = {
    title: string,
    compiledCode: string
}
export type PlutusCompiled = {
    validators: PlutusValidatorCompiled[]
}

export function readValidators(): StableswapValidators {
    const file = fs.readFileSync("plutus.json", "utf-8");
    const plutusCompiled: PlutusCompiled = JSON.parse(file);
    const orderValidator = plutusCompiled.validators.find((v: any) => v.title === "order_validator.validate_order")
    const poolValidator = plutusCompiled.validators.find((v: any) => v.title === "pool_validator.validate_pool")
    const lpMinting = plutusCompiled.validators.find((v: any) => v.title === "lp_minting_policy.validate_lp_minting")
    const orderBatchingValidator = plutusCompiled.validators.find((v: any) => v.title === "order_validator.validate_order_spending_in_batching")

    if (!orderValidator || !poolValidator || !lpMinting || !orderBatchingValidator) {
        throw Error("Validator not found")
    }

    return {
        orderScript: {
            type: "PlutusV2",
            script: orderValidator.compiledCode
        },
        poolScript: {
            type: "PlutusV2",
            script: poolValidator.compiledCode
        },
        lpMinting: {
            type: "PlutusV2",
            script: lpMinting.compiledCode
        },
        orderBatchingScript: {
            type: "PlutusV2",
            script: orderBatchingValidator.compiledCode
        }
    }
}

export async function buildScripts(
    network: NetworkID,
    lucid: Lucid,
    validators: StableswapValidators,
    poolConfig: PoolConfig,
): Promise<BuildScriptResponse> {
    const lpMinting = applyParamsToScript(assetToPlutusData(poolConfig.nftAsset), validators.lpMinting.script)

    const policyId = lucid.utils.validatorToScriptHash({
        type: "PlutusV2",
        script: lpMinting
    })

    const lpAsset: Asset = {
        policyId: policyId,
        tokenName: poolConfig.nftAsset.tokenName
    }

    const poolParams: PoolParams = {
        nftAsset: poolConfig.nftAsset,
        lpAsset: lpAsset,
        licenseSymbol: poolConfig.licenseSymbol,
        adminAsset: poolConfig.adminAsset,
        maximumDeadlineRange: poolConfig.maximumDeadlineRange,
        assets: poolConfig.assets,
        multiples: poolConfig.multiples,
        fee: poolConfig.fee,
        adminFee: poolConfig.adminFee,
        denominator: poolConfig.feeDenominator
    }

    const poolScript = applyParamsToScript(poolParamsToPlutusData(poolParams), validators.poolScript.script)
    const poolHash = lucid.utils.validatorToScriptHash({
        type: "PlutusV2",
        script: poolScript
    })

    const poolHashPlutusData = C.PlutusData.new_bytes(bytesFromHex(poolHash))

    const orderBatchingScript = applyParamsToScript(poolHashPlutusData, validators.orderBatchingScript.script)
    const orderBatchingHash = lucid.utils.validatorToScriptHash({
        type: "PlutusV2",
        script: orderBatchingScript,
    });

    const orderBatchingAddr = C.RewardAddress.new(
        network === NetworkID.TESTNET ? 0 : 1,
        C.StakeCredential.from_scripthash(C.ScriptHash.from_hex(orderBatchingHash))
    ).to_address().to_bech32(undefined)

    const orderScript = applyParamsToScript(buildStakeCredPlutusData(orderBatchingHash), validators.orderScript.script)

    const orderHash = lucid.utils.validatorToScriptHash({
        type: "PlutusV2",
        script: orderScript
    })

    let poolAddr: string
    let orderAddr: string
    if (poolConfig.stakeCredential) {
        poolAddr = C.BaseAddress.new(
            network === NetworkID.TESTNET ? 0 : 1,
            C.StakeCredential.from_scripthash(C.ScriptHash.from_hex(poolHash)),
            poolConfig.stakeCredential
        ).to_address().to_bech32(undefined)
        orderAddr = C.BaseAddress.new(
            network === NetworkID.TESTNET ? 0 : 1,
            C.StakeCredential.from_scripthash(C.ScriptHash.from_hex(orderHash)),
            poolConfig.stakeCredential
        ).to_address().to_bech32(undefined)
    } else {
        poolAddr = C.EnterpriseAddress.new(
            network === NetworkID.TESTNET ? 0 : 1,
            C.StakeCredential.from_scripthash(C.ScriptHash.from_hex(poolHash)),
        ).to_address().to_bech32(undefined)
        orderAddr = C.EnterpriseAddress.new(
            network === NetworkID.TESTNET ? 0 : 1,
            C.StakeCredential.from_scripthash(C.ScriptHash.from_hex(orderHash)),
        ).to_address().to_bech32(undefined)
    }

    const res: BuildScriptResponse = {
        key: poolConfig.dirName,
        orderScript: orderScript,
        poolScript: poolScript,
        lpScript: lpMinting,
        orderBatchingScript: orderBatchingScript,
        orderAddress: orderAddr,
        poolAddress: poolAddr,
        orderBatchingAddress: orderBatchingAddr,
        licenseSymbol: poolParams.licenseSymbol,
        adminAsset: poolParams.adminAsset,
        nftAsset: poolConfig.nftAsset,
        lpAsset: lpAsset,
        assets: poolConfig.assets,
        multiples: poolConfig.multiples.map((m) => m.toString()),
        fee: poolConfig.fee.toString(),
        adminFee: poolConfig.adminFee.toString(),
        feeDenominator: poolConfig.feeDenominator.toString()
    }
    return res
}

type PoolConfig = {
    dirName: string;
    nftAsset: Asset;
    assets: Asset[];
    multiples: bigint[];
    fee: bigint;
    adminFee: bigint;
    feeDenominator: bigint;
    licenseSymbol: string;
    adminAsset: Asset;
    maximumDeadlineRange: bigint;
    stakeCredential?: C.StakeCredential
}

const POOL_CONFIGS: Record<NetworkID, PoolConfig[]> = {
    mainnet: [
        {
            dirName: "djed-iusd",
            nftAsset: {
                policyId: "5d4b6afd3344adcf37ccef5558bb87f522874578c32f17160512e398",
                tokenName: fromText("DJED-iUSD-SLP")
            },
            assets: [
                // DJED
                {
                    policyId: "8db269c3ec630e06ae29f74bc39edd1f87c819f1056206e879a1cd61",
                    tokenName: "446a65644d6963726f555344"
                },
                // iUSD
                {
                    policyId: "f66d78b4a3cb3d37afa0ec36461e51ecbde00f26c8f0a68f94b69880",
                    tokenName: "69555344"
                }
            ],
            multiples: [1n, 1n],
            fee: MAINNET_FEE,
            adminFee: MAINNET_ADMIN_FEE,
            feeDenominator: MAINNET_FEE_DENOMINATOR,
            licenseSymbol: MAINNET_BATCHER_LICENSE_SYMBOL,
            adminAsset: MAINNET_ADMIN_ASSET,
            maximumDeadlineRange: MAINNET_MAXIMUM_DEADLINE_RANGE,
        },
        {
            dirName: "usdc-djed",
            nftAsset: {
                policyId: "d97fa91daaf63559a253970365fb219dc4364c028e5fe0606cdbfff9",
                tokenName: fromText("USDC-DJED-SLP")
            },
            assets: [
                // USDC
                {
                    policyId: "25c5de5f5b286073c593edfd77b48abc7a48e5a4f3d4cd9d428ff935",
                    tokenName: "55534443"
                },
                // DJED
                {
                    policyId: "8db269c3ec630e06ae29f74bc39edd1f87c819f1056206e879a1cd61",
                    tokenName: "446a65644d6963726f555344"
                }
            ],
            multiples: [1n, 100n],
            fee: MAINNET_FEE,
            adminFee: MAINNET_ADMIN_FEE,
            feeDenominator: MAINNET_FEE_DENOMINATOR,
            licenseSymbol: MAINNET_BATCHER_LICENSE_SYMBOL,
            adminAsset: MAINNET_ADMIN_ASSET,
            maximumDeadlineRange: MAINNET_MAXIMUM_DEADLINE_RANGE,
        },
        {
            dirName: "usdm-iusd",
            nftAsset: {
                policyId: "96402c6f5e7a04f16b4d6f500ab039ff5eac5d0226d4f88bf5523ce8",
                tokenName: fromText("USDM-iUSD-SLP")
            },
            assets: [
                // USDM
                {
                    policyId: "c48cbb3d5e57ed56e276bc45f99ab39abe94e6cd7ac39fb402da47ad",
                    tokenName: "0014df105553444d"
                },
                // iUSD
                {
                    policyId: "f66d78b4a3cb3d37afa0ec36461e51ecbde00f26c8f0a68f94b69880",
                    tokenName: "69555344"
                }
            ],
            multiples: [1n, 1n],
            fee: MAINNET_FEE,
            adminFee: MAINNET_ADMIN_FEE,
            feeDenominator: MAINNET_FEE_DENOMINATOR,
            licenseSymbol: MAINNET_BATCHER_LICENSE_SYMBOL,
            adminAsset: MAINNET_ADMIN_ASSET,
            maximumDeadlineRange: MAINNET_MAXIMUM_DEADLINE_RANGE,
        }
    ],
    testnet: [
        {
            dirName: "djed-iusd",
            nftAsset: {
                policyId: TESTNET_POOL_NFT_SYMBOL,
                tokenName: "646a65642d697573642d76312e342d6c70" // djed-iusd-v1.4-lp
            },
            assets: [{
                policyId: TESTNET_ASSET_SYMBOL,
                tokenName: "74444a4544" // tDJED
            },
            {
                policyId: TESTNET_ASSET_SYMBOL,
                tokenName: "7469555344" // tiUSD
            }],
            multiples: [1n, 1n],
            fee: TESTNET_FEE,
            adminFee: TESTNET_ADMIN_FEE,
            feeDenominator: TESTNET_FEE_DENOMINATOR,
            licenseSymbol: TESTNET_LICENSE_SYMBOL,
            adminAsset: TESTNET_ADMIN_ASSET,
            maximumDeadlineRange: TESTNET_MAXIMUM_DEADLINE_RANGE,
            stakeCredential: TESTNET_STAKE_CREDENTIAL
        },
        {
            dirName: "usdc-usdt",
            nftAsset: {
                policyId: TESTNET_POOL_NFT_SYMBOL,
                tokenName: "757364632d757364742d76312e342d6c70" // usdc-usdt-v1.4-lp
            },
            assets: [{
                policyId: TESTNET_ASSET_SYMBOL,
                tokenName: "7455534443" // tUSDC
            },
            {
                policyId: TESTNET_ASSET_SYMBOL,
                tokenName: "7455534454" // tUSDT
            }],
            multiples: [1n, 1n],
            fee: TESTNET_FEE,
            adminFee: TESTNET_ADMIN_FEE,
            feeDenominator: TESTNET_FEE_DENOMINATOR,
            licenseSymbol: TESTNET_LICENSE_SYMBOL,
            adminAsset: TESTNET_ADMIN_ASSET,
            maximumDeadlineRange: TESTNET_MAXIMUM_DEADLINE_RANGE,
            stakeCredential: TESTNET_STAKE_CREDENTIAL
        },
        {
            dirName: "djed-iusd-dai",
            nftAsset: {
                policyId: TESTNET_POOL_NFT_SYMBOL,
                tokenName: "646a65642d697573642d6461692d76312e342d6c70" // djed-iusd-dai-v1.4-lp
            },
            assets: [{
                policyId: TESTNET_ASSET_SYMBOL,
                tokenName: "74444a4544" // tDJED
            },
            {
                policyId: TESTNET_ASSET_SYMBOL,
                tokenName: "7469555344" // tiUSD
            },
            {
                policyId: TESTNET_ASSET_SYMBOL,
                tokenName: "74444149" // tDAI
            }],
            multiples: [1n, 1n, 1n],
            fee: TESTNET_FEE,
            adminFee: TESTNET_ADMIN_FEE,
            feeDenominator: TESTNET_FEE_DENOMINATOR,
            licenseSymbol: TESTNET_LICENSE_SYMBOL,
            adminAsset: TESTNET_ADMIN_ASSET,
            maximumDeadlineRange: TESTNET_MAXIMUM_DEADLINE_RANGE,
            stakeCredential: TESTNET_STAKE_CREDENTIAL
        }
    ],
}

type BuildScriptResponse = {
    key: string,
    orderScript: string,
    poolScript: string,
    lpScript: string,
    orderBatchingScript: string,
    orderAddress: string,
    poolAddress: string,
    orderBatchingAddress: string,
    licenseSymbol: string,
    adminAsset: Asset,
    nftAsset: Asset,
    lpAsset: Asset,
    assets: Asset[],
    multiples: string[],
    fee: string,
    adminFee: string,
    feeDenominator: string
}

async function main() {
    const validators = readValidators()

    for (const [network, configs] of Object.entries(POOL_CONFIGS)) {
        switch (network) {
            case NetworkID.MAINNET: {
                const lucid = await Lucid.new(undefined, "Mainnet")
                const buildScriptResponses: BuildScriptResponse[] = []
                for (const poolConfig of configs) {
                    const res = await buildScripts(network, lucid, validators, poolConfig)
                    buildScriptResponses.push(res)
                }

                fs.writeFileSync(`scripts/${network}/stableswap-script.json`, JSON.stringify(buildScriptResponses, null, 4))
                break;
            }
            case NetworkID.TESTNET: {
                const lucid = await Lucid.new(undefined, "Preprod")
                const buildScriptResponses: BuildScriptResponse[] = []
                for (const poolConfig of configs) {
                    const res = await buildScripts(network, lucid, validators, poolConfig)
                    buildScriptResponses.push(res)
                }

                fs.writeFileSync(`scripts/${network}/stableswap-script.json`, JSON.stringify(buildScriptResponses, null, 4))
                break
            }
            default: {
                throw Error("Unexpected Network")
            }
        }
    }
}

main()