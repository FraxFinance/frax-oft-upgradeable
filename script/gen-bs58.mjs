import { VersionedMessage, VersionedTransaction } from '@solana/web3.js'
import bs58 from 'bs58'
import fs from "fs"
import path from "path"
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// Map token filenames to token names
const tokenNameMap = {
  'wfrax-upgrade-dvn.json': 'wfrax',
  'frxeth-upgrade-dvn.json': 'frxeth',
  'frxusd-upgrade-dvn.json': 'frxusd',
  'sfrxeth-upgrade-dvn.json': 'sfrxeth',
  'sfrxusd-upgrade-dvn.json': 'sfrxusd',
  'fpi-upgrade-dvn.json': 'fpi'
}

// Map destination eids to chain names
const chainNameMap = {
  30101: 'ethereum',
  30255: 'fraxtal'
}

const sourceDir = path.join(__dirname, '../solana-raw-transactions/add-canary-nethermind')
const outputDir = path.join(__dirname, '../scripts/ops/fix/FixDVNs/generated/canary-nethermind/solana/2-solana-upgrade-dvn')

// Ensure output directory exists
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true })
}

// Read all JSON files from source directory
const jsonFiles = fs.readdirSync(sourceDir).filter(file => file.endsWith('.json'))
let txCount = 0

jsonFiles.forEach(jsonFile => {
  const tokenName = tokenNameMap[jsonFile]
  if (!tokenName) {
    console.warn(`Unknown token file: ${jsonFile}`)
    return
  }

  const filePath = path.join(sourceDir, jsonFile)
  const rawData = fs.readFileSync(filePath, 'utf8')
  const txDataArray = JSON.parse(rawData)

  txDataArray.forEach((txData, index) => {
    // Only process Solana side (eid 30168)
    if (txData.point.eid !== 30168) {
      return
    }

    // Extract destination eid and configType from description
    const descMatch = txData.description.match(/"eid":\s*(\d+)/)
    const configTypeMatch = txData.description.match(/"configType":\s*(\d+)/)
    if (!descMatch || !configTypeMatch) {
      console.warn(`Could not extract eid/configType from description for ${jsonFile}`)
      return
    }

    const dstEid = parseInt(descMatch[1])
    const configType = parseInt(configTypeMatch[1])
    const chainName = chainNameMap[dstEid]
    if (!chainName) {
      console.warn(`Unknown destination eid: ${dstEid}`)
      return
    }

    // Deserialize and convert to base58
    try {
      const tx = new VersionedTransaction(VersionedMessage.deserialize(Buffer.from(txData.data, 'hex')))
      const base58Tx = bs58.encode(Buffer.from(tx.serialize()))

      // Generate filename: upgradeDVN-{tokenName}-{dstChain}-ct{configType}.txt
      const filename = `upgradeDVN-${tokenName}-${chainName}-ct${configType}.txt`
      const outputPath = path.join(outputDir, filename)

      fs.writeFileSync(outputPath, base58Tx, 'utf8')
      console.log(`✓ Generated: ${filename}`)
      txCount++
    } catch (error) {
      console.error(`Error processing transaction for ${jsonFile}:`, error.message)
    }
  })
})

console.log(`\nTotal transactions processed: ${txCount}`)
console.log(`Output directory: ${outputDir}`)
