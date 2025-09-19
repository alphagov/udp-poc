import json
import boto3
import os

dynamodb = boto3.client('dynamodb')
table_name = os.environ['DYNAMODB_TABLE_NAME']

def handler(event, context):
    """
    Athena data source connector for DynamoDB
    """
    try:
        # Get table schema
        response = dynamodb.describe_table(TableName=table_name)
        table_info = response['Table']
        
        # Scan the table to get sample data
        scan_response = dynamodb.scan(
            TableName=table_name,
            Limit=100
        )
        
        # Return data in Athena-compatible format
        return {
            'statusCode': 200,
            'body': json.dumps({
                'table_name': table_name,
                'items': scan_response.get('Items', []),
                'schema': {
                    'user_id': 'S',
                    'setting_key': 'S',
                    'value': 'S',
                    'updated_at': 'S'
                }
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
