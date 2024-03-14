import {bls12_381 as bls} from "@noble/curves/bls12-381";

const private_key = bls.utils.randomPrivateKey();
const public_key = bls.getPublicKey(private_key);
console.log("Public key: ", public_key.toString());

const message = new Uint8Array([1,2,3,4]);;
const signature = bls.sign(message, private_key);
console.log("\nsignature :", signature.toString());

const isValid = bls.verify(signature, message, public_key);
console.log("\nisValid: ", isValid);