import { getAddress, zeroAddress } from 'viem'
import { ChainConfig } from '../types'
import { default as lzfrxUSD } from './check-oft-config-csv/check-frxUSD-config-peer.json'
import fs from 'fs'

function isWiredX(config: ChainConfig, srcChain: string, dstChain: string): boolean {
    const src = config[srcChain]
    const dst = config[dstChain]
    if (!src || !dst) return false

    const srcDst = src.dstChains?.[dstChain]
    const dstSrc = dst.dstChains?.[srcChain]
    if (!srcDst || !dstSrc) return false

    const srcOft = src.params.oftProxy
    const dstOft = dst.params.oftProxy
    const srcOftOnDst = getAddress(dstSrc.peerAddress || zeroAddress)
    const dstOftOnSrc = getAddress(srcDst.peerAddress || zeroAddress)

    const srcSendLib = getAddress(srcDst.sendLibrary || zeroAddress)
    const srcBlockedLib = getAddress(srcDst.blockedLib || zeroAddress)
    const dstSendLib = getAddress(dstSrc.sendLibrary || zeroAddress)
    const dstBlockedLib = getAddress(dstSrc.blockedLib || zeroAddress)

    return (
        srcOft === srcOftOnDst && dstOft === dstOftOnSrc && srcSendLib !== srcBlockedLib && dstSendLib !== dstBlockedLib
    )
}

export function generateExecutorConfigCSV(config: any): string {
    const chains = Object.keys(config)
    const rows: string[][] = []

    // Header
    rows.push([
        'srcChain',
        'dstChain',
        'defaultExecutorConfig.maxMessageSize',
        'defaultExecutorConfig.executorAddress',
        '',
        'executorConfig.maxMessageSize',
        'executorConfig.executorAddress',
    ])

    const asStr = (v?: string | number) => (v !== undefined ? String(v) : '-')

    for (const srcChain of chains) {
        for (const dstChain of chains) {
            if (
                srcChain === 'aptos' ||
                srcChain === 'solana' ||
                srcChain === 'movement' ||
                dstChain === 'aptos' ||
                dstChain === 'solana' ||
                dstChain === 'movement'
            ) {
                continue
            }
            if (srcChain === dstChain) continue
            if (!isWiredX(config, srcChain, dstChain)) continue

            const dstCfg = config[srcChain]?.dstChains?.[dstChain]
            if (!dstCfg) continue

            const def = dstCfg.defaultExecutorConfig ?? ["-","-"]
            const app = dstCfg.executorConfig ?? ["-","-"]

            rows.push([
                srcChain,
                dstChain,
                asStr(def[0]),
                asStr(def[1]),
                '',
                asStr(app[0]),
                asStr(app[1]),
            ])
        }
    }

    return rows.map((r) => r.join(',')).join('\n')
}

async function main() {
    fs.writeFileSync(
        `./run-periodically/check-oft-config-csv/check-executorConfig-lzfrxUSD-peer.csv`,
        generateExecutorConfigCSV(lzfrxUSD)
    )
}

main()
