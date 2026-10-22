// Independent implementation: Node/OpenSSL <-> Windows CNG, DER ECDSA P-256.
const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const dir = process.argv[2];
const payload = fs.readFileSync(path.join(dir, 'payload.bin'));
const signature = fs.readFileSync(path.join(dir, 'signature.bin'));
const publicKey = fs.readFileSync(path.join(dir, 'public.pem'));
if (!crypto.verify('sha256', payload, publicKey, signature)) throw Error('License signature mismatch');
const proof = JSON.parse(fs.readFileSync(path.join(dir, 'proof.json'), 'utf8'));
const { signature: proofSig, ...unsigned } = proof;
const prefix = Buffer.from('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex');
const proofKey = crypto.createPublicKey({
  key: Buffer.concat([prefix, Buffer.from(proof.public_key, 'base64url')]), type: 'spki', format: 'der'
});
if (!crypto.verify('sha256', Buffer.from('GlassFolders-GFP1-v1\n' + JSON.stringify(unsigned)),
    proofKey, Buffer.from(proofSig, 'base64url'))) throw Error('Proof signature mismatch');
const pair = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
fs.writeFileSync(path.join(dir, 'node-public.der'), pair.publicKey.export({type:'spki', format:'der'}));
fs.writeFileSync(path.join(dir, 'node-signature.bin'), crypto.sign('sha256', payload, pair.privateKey));
console.log('Independent Node/OpenSSL verified license and device proof; generated reverse signature.');
