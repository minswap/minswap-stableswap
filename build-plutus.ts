import {
    Lucid,
    MintingPolicy,
    SpendingValidator,
    fromHex,
    C
} from "lucid-cardano";
import * as fs from "fs";
import { promisify } from "util";
import { exec } from "child_process";

export type StableswapValidators = {
    orderScript: SpendingValidator;
    poolScript: SpendingValidator;
    lpMinting: MintingPolicy
}

enum NetworkID {
    MAINNET = "mainnet",
    TESTNET = "testnet"
}

type Asset = {
    policyId: string,
    tokenName: string
}

const MAINNET_MAXIMUM_DEADLINE_RANGE = 7776000000n; // 90 days
const TESTNET_MAXIMUM_DEADLINE_RANGE = 77760000000n; // 900 days
const TESTNET_FEE = 1000000n
const TESTNET_ADMIN_FEE = 5000000000n
const TESTNET_FEE_DENOMINATOR = 10000000000n
const TESTNET_ASSET_SYMBOL = "e16c2dc8ae937e8d3790c7fd7168d7b994621ba14ca11415f39fed72"
const TESTNET_POOL_NFT_SYMBOL = "06fe1ba957728130154154d5e5b25a7b533ebe6c4516356c0aa69355"
const TESTNET_LICENSE_SYMBOL = "defbf038da8ec085f9a304f13946f34522c2f7866bac9def8391685b"
// const MAINNET_LICENSE_SYMBOL = "defbf038da8ec085f9a304f13946f34522c2f7866bac9def8391685b"
const TESTNET_ADMIN_ASSET: Asset = {
    policyId: "defbf038da8ec085f9a304f13946f34522c2f7866bac9def8391685b",
    tokenName: "41444d494e"
}
// const MAINNET_ADMIN_ASSET: Asset = {
//     policyId: "defbf038da8ec085f9a304f13946f34522c2f7866bac9def8391685b",
//     tokenName: "41444d494e"
// }

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

    if (!orderValidator || !poolValidator || !lpMinting) {
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
    const orderScript = applyParamsToScript(poolHashPlutusData, validators.orderScript.script)
    const lpPlutus = {
        "type": "PlutusScriptV2",
        "description": "",
        "cborHex": lpMinting
    }
    const poolPlutus = {
        "type": "PlutusScriptV2",
        "description": "",
        "cborHex": poolScript
    }
    const orderPlutus = {
        "type": "PlutusScriptV2",
        "description": "",
        "cborHex": orderScript
    }

    fs.writeFileSync(`scripts/${network}/${poolConfig.dirName}/lp_minting_policy.plutus`, JSON.stringify(lpPlutus, null, 4))
    fs.writeFileSync(`scripts/${network}/${poolConfig.dirName}/pool_script.plutus`, JSON.stringify(poolPlutus, null, 4))
    fs.writeFileSync(`scripts/${network}/${poolConfig.dirName}/order_script.plutus`, JSON.stringify(orderPlutus, null, 4))

    const orderCommandResult = await promisify(exec)(
        `cardano-cli address build --payment-script-file scripts/${network}/${poolConfig.dirName}/order_script.plutus --stake-verification-key-file keys/${network}/stake.vkey --testnet-magic 1`,
    );
    const orderAddress = orderCommandResult.stdout
    const poolCommandResult = await promisify(exec)(
        `cardano-cli address build --payment-script-file scripts/${network}/${poolConfig.dirName}/pool_script.plutus --stake-verification-key-file keys/${network}/stake.vkey --testnet-magic 1`,
    );
    const poolAddress = poolCommandResult.stdout

    const res: BuildScriptResponse = {
        key: poolConfig.dirName,
        orderScript: orderScript,
        poolScript: poolScript,
        lpScript: lpMinting,
        orderAddress: orderAddress,
        poolAddress: poolAddress,
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
}

const POOL_CONFIGS: Record<NetworkID, PoolConfig[]> = {
    mainnet: [],
    testnet: [
        {
            dirName: "djed-iusd",
            nftAsset: {
                policyId: TESTNET_POOL_NFT_SYMBOL,
                tokenName: "646a65642d697573642d76312e322d6c70" // djed-iusd-v1.2-lp
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
            maximumDeadlineRange: TESTNET_MAXIMUM_DEADLINE_RANGE
        },
        {
            dirName: "usdc-usdt",
            nftAsset: {
                policyId: TESTNET_POOL_NFT_SYMBOL,
                tokenName: "757364632d757364742d76312e322d6c70" // usdc-usdt-v1.2-lp
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
            maximumDeadlineRange: TESTNET_MAXIMUM_DEADLINE_RANGE
        },
        {
            dirName: "djed-iusd-dai",
            nftAsset: {
                policyId: TESTNET_POOL_NFT_SYMBOL,
                tokenName: "646a65642d697573642d6461692d76312e322d6c70" // djed-iusd-dai-v1.2-lp
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
            maximumDeadlineRange: TESTNET_MAXIMUM_DEADLINE_RANGE
        }
    ],
}

type BuildScriptResponse = {
    key: string,
    orderScript: string,
    poolScript: string,
    lpScript: string,
    orderAddress: string,
    poolAddress: string,
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
                fs.writeFileSync(`../packages/sdk/src/stableswap/scripts/${network}/stableswap-script.json`, JSON.stringify(buildScriptResponses, null, 4))
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
                fs.writeFileSync(`../packages/sdk/src/stableswap/scripts/${network}/stableswap-script.json`, JSON.stringify(buildScriptResponses, null, 4))
                break
            }
            default: {
                throw Error("Unexpected Network")
            }
        }
    }
}

main()