import { TronWeb, Types as TronWebTypes, Types } from 'tronweb'
import L0ConfigJson from '../../../../L0Config.json'
import { L0Config } from './types'

export function setUp(): { broadcastConfig: L0Config; allConfigs: L0Config[] } {
    // The final array
    const allConfigs: L0Config[] = []

    let broadcastConfig: L0Config | null = null

    // Push everything from Legacy
    if (Array.isArray(L0ConfigJson.Legacy)) {
        allConfigs.push(...L0ConfigJson.Legacy)
    }

    // Push from Proxy, with filtering on chainid
    if (Array.isArray(L0ConfigJson.Proxy)) {
        const filtered = L0ConfigJson.Proxy.filter((cfg) => ![1, 81457, 1088, 8453].includes(cfg.chainid))
        allConfigs.push(...filtered)
    }

    // Push everything from Non-EVM
    if (Array.isArray(L0ConfigJson['Non-EVM'])) {
        allConfigs.push(...L0ConfigJson['Non-EVM'])
    }

    for (let e = 0; e < allConfigs.length; e++) {
        if (allConfigs[e].eid === 30420) {
            // search for eid 30420 or chainid 728126428
            broadcastConfig = allConfigs[e]
            break
        }
    }

    if (broadcastConfig === null) {
        throw new Error('broadcast config not found. Please check tronbox and L0 config files')
    }

    return { broadcastConfig, allConfigs }
}

export async function preDeployChecks(
    _allConfigs: L0Config[],
    _broadcastConfig: L0Config,
    endpointInstance: Types.ContractInstance<Types.ContractAbiInterface>
) {
    for (const config of _allConfigs) {
        if (config.eid === _broadcastConfig.eid) continue

        // L0 team has not setup defaultSendLibrary and defaultReceiveLibrary on tron mainnet for
        // 30370 (plume), botanix (30376), katana (30375), hyperliquid (30367), movement (30325)
        // and aptos (30108)
        if (
            config.eid === 30370 ||
            config.eid === 30376 ||
            config.eid === 30375 ||
            config.eid === 30367 ||
            config.eid === 30325 ||
            config.eid === 30108
        )
            continue
        const eid = Number(config.eid)
        try {
            const isSupported = await endpointInstance.isSupportedEid(eid).call()
            console.log(isSupported)
            if (!isSupported) {
                throw new Error(`L0 team required to setup defaultSendLibrary and defaultReceiveLibrary for ${eid}`)
            }
        } catch (error) {
            console.error(error)
        }
    }
}

export async function deployContract(
    tronWeb: TronWeb,
    abi: any,
    bytecode: any,
    parameters: any[]
): Promise<TronWebTypes.ContractInstance<TronWebTypes.ContractAbiInterface>> {
    const instance = await tronWeb.contract().new({
        abi: abi,
        bytecode: bytecode.object,
        feeLimit: 1000000000,
        callValue: 0,
        userFeePercentage: 1,
        originEnergyLimit: 10000000,
        parameters,
    })
    return instance
}
