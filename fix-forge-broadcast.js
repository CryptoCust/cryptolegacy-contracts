const fs = require('fs');
const https = require('https');

const rpc = process.env.RPC;
const networkId = process.env.NETWORK_ID;
const scriptName = 'CryptoLegacyFactory.s.sol';

const broadcastPath = `./broadcast/${scriptName}/${networkId}/run-latest.json`;

const forgeBroadcast = JSON.parse(fs.readFileSync(broadcastPath));

(async () => {
  for (let i = 0; i < forgeBroadcast.transactions.length; i++) {
    const tx = forgeBroadcast.transactions[i];
    if (!tx.hash) {
      continue;
    }
    if (!forgeBroadcast.receipts.filter(r => r && r.transactionHash === tx.hash)[0]) {
      const receipt = await getTransactionReceipt(tx.hash);
      forgeBroadcast.receipts[i] = receipt;
    }
  }

  fs.writeFileSync(broadcastPath, JSON.stringify(forgeBroadcast, null, 2));
})();

function getTransactionReceipt(txHash) {
  return new Promise((resolve, reject) => {
    const rpcData = JSON.stringify({
      jsonrpc: '2.0',
      method: 'eth_getTransactionReceipt',
      params: [txHash],
      id: 1,
    });

    const options = {
      hostname: rpc.split('/')[0],
      port: 443,
      path: '/' + rpc.split('/').slice(1).join('/') + '/',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(rpcData),
      },
    };

    const req = https.request(options, (res) => {
      let raw = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { raw += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(raw);
          if (parsed.error) {
            reject(new Error(parsed.error.message));
          } else {
            resolve(parsed.result);  // may be null if pending
          }
        } catch (err) {
          reject(err);
        }
      });
    });

    req.on('error', reject);
    req.write(rpcData);
    req.end();
  });
}
