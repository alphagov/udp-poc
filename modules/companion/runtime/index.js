'use strict';

const { AthenaClient, StartQueryExecutionCommand, GetQueryExecutionCommand, GetQueryResultsCommand } = require('@aws-sdk/client-athena');

const bucket = process.env.BUCKET_NAME;
const database = process.env.DATABASE_NAME;
const workgroup = process.env.WORKGROUP_NAME;

exports.handler = async (event) => {
  try {
    const userId = event.pathParameters && event.pathParameters.user_id;
    if (!userId) return response(400, { message: 'user_id is required' });

    const athena = new AthenaClient({});
    const query = `SELECT new.setting_key AS setting_key, new.value AS value, ts FROM ${database}.app_settings_raw WHERE keys.user_id='${userId}' ORDER BY ts DESC LIMIT 100`;
    const start = await athena.send(new StartQueryExecutionCommand({
      QueryString: query,
      WorkGroup: workgroup,
      QueryExecutionContext: { Database: database }
    }));
    const qid = start.QueryExecutionId;
    await waitForQuery(athena, qid);
    const res = await athena.send(new GetQueryResultsCommand({ QueryExecutionId: qid }));
    const rows = parseAthenaRows(res);
    const settings = {};
    for (const r of rows) {
      if (!settings[r.setting_key]) settings[r.setting_key] = { value: r.value, updated_at: r.ts };
    }
    return response(200, { user_id: userId, settings });
  } catch (err) {
    console.error(err);
    return response(500, { message: 'Internal Server Error' });
  }
};

function response(statusCode, body) {
  return { statusCode, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}

async function waitForQuery(client, id) {
  while (true) {
    const q = await client.send(new GetQueryExecutionCommand({ QueryExecutionId: id }));
    const state = q?.QueryExecution?.Status?.State;
    if (state === 'SUCCEEDED') return;
    if (state === 'FAILED' || state === 'CANCELLED') throw new Error(`Athena ${state}`);
    await new Promise(r => setTimeout(r, 500));
  }
}

function parseAthenaRows(res) {
  const rows = res?.ResultSet?.Rows || [];
  if (rows.length <= 1) return [];
  const headers = rows[0].Data.map(d => d.VarCharValue);
  const out = [];
  for (let i = 1; i < rows.length; i++) {
    const obj = {};
    const cols = rows[i].Data;
    for (let j = 0; j < headers.length; j++) obj[headers[j]] = cols[j]?.VarCharValue ?? null;
    out.push(obj);
  }
  return out;
}


