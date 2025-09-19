'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');

const tableName = process.env.TABLE_NAME;
const domainName = process.env.DOMAIN_NAME;
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

exports.handler = async (event) => {
  try {
    const method = event.requestContext.http.method;
    const path = event.requestContext.http.path || '';
    const params = event.pathParameters || {};

    if (method === 'GET' && path.startsWith('/')) {
      const userId = params.user_id;
      if (!userId) return response(400, { message: 'user_id is required' });

      // Query all items for user
      const res = await ddb.send(new QueryCommand({
        TableName: tableName,
        KeyConditionExpression: '#u = :u',
        ExpressionAttributeNames: { '#u': 'user_id' },
        ExpressionAttributeValues: { ':u': userId }
      }));
      
      return response(200, { 
        domain: domainName,
        user_id: userId, 
        items: res.Items || [] 
      });
    }

    if (method === 'PUT' && path.includes('/')) {
      const { user_id, item_key } = params;
      if (!user_id || !item_key) return response(400, { message: 'user_id and item_key are required' });
      
      const body = parseBody(event.body);
      if (!body || typeof body.value === 'undefined') return response(400, { message: 'body.value is required' });

      await ddb.send(new PutCommand({
        TableName: tableName,
        Item: {
          user_id,
          item_key,
          value: body.value,
          updated_at: new Date().toISOString()
        }
      }));
      
      return response(204);
    }

    return response(404, { message: 'Not found' });
  } catch (err) {
    console.error(err);
    return response(500, { message: 'Internal Server Error' });
  }
};

function parseBody(body) {
  if (!body) return null;
  try { return JSON.parse(body); } catch { return null; }
}

function response(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined
  };
}
