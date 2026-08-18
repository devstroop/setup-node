'use strict'

const major = Number(process.versions.node.split('.')[0])
if (!Number.isInteger(major) || major < 10) {
  console.error(`unexpected node major: ${process.versions.node}`)
  process.exit(1)
}

console.log(`hello from node ${process.version} (npm ${process.versions.npm})`)
if (!process.env.NODE_DIR) {
  console.error('NODE_DIR env var not set')
  process.exit(1)
}
console.log(`NODE_DIR=${process.env.NODE_DIR}`)