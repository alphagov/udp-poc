'use strict';

const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const s3 = new S3Client({});

const bucket = process.env.BUCKET_NAME;
const product = process.env.PRODUCT_NAME || 'app_settings';

exports.handler = async (event) => {
  const puts = [];
  for (const rec of event.Records || []) {
    const { eventName, dynamodb } = rec;
    const keys = unmarshall(dynamodb.Keys || {});
    const newImage = unmarshall(dynamodb.NewImage || {});
    const oldImage = unmarshall(dynamodb.OldImage || {});

    const ts = new Date().toISOString();
    const payload = {
      op: eventName, // INSERT | MODIFY | REMOVE
      keys,
      new: newImage,
      old: oldImage,
      ts
    };

    const userId = (keys.user_id || newImage.user_id || 'unknown').toString();
    const day = ts.substring(0, 10);
    const key = `products/${product}/raw/dt=${day}/user_id=${encodeURIComponent(userId)}/${ts}-${randomId()}.json`;

    puts.push(s3.send(new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      ContentType: 'application/json',
      Body: JSON.stringify(payload)
    })));
  }

  await Promise.all(puts);
  return { statusCode: 200 };
};

function unmarshall(m) {
  // Minimal DynamoDB JSON (streams) to plain JS converter
  const out = {};
  for (const [k, v] of Object.entries(m)) {
    if ('S' in v) out[k] = v.S;
    else if ('N' in v) out[k] = Number(v.N);
    else if ('BOOL' in v) out[k] = v.BOOL;
    else if ('NULL' in v) out[k] = null;
    else if ('M' in v) out[k] = unmarshall(v.M);
    else if ('L' in v) out[k] = v.L.map(unmarshallValue);
  }
  return out;
}

function unmarshallValue(v) {
  if ('S' in v) return v.S;
  if ('N' in v) return Number(v.N);
  if ('BOOL' in v) return v.BOOL;
  if ('NULL' in v) return null;
  if ('M' in v) return unmarshall(v.M);
  if ('L' in v) return v.L.map(unmarshallValue);
  return v;
}

function randomId() {
  return Math.random().toString(36).slice(2, 10);
}


