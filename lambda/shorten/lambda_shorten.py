import json
import boto3
import string
import random
import os
from datetime import datetime

s3 = boto3.client('s3')
BUCKET = os.environ.get('S3_BUCKET', 'my-url-shortener-bucket')
BASE_URL = os.environ.get('BASE_URL', 'https://short.ly')

def generate_code(length=6):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choices(chars, k=length))

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        long_url = body.get('url', '').strip()

        if not long_url or not long_url.startswith(('http://', 'https://')):
            return response(400, {'error': 'A valid URL (http/https) is required.'})

        code = generate_code()
        payload = {
            'original_url': long_url,
            'short_code': code,
            'created_at': datetime.utcnow().isoformat(),
            'hits': 0
        }

        s3.put_object(
            Bucket=BUCKET,
            Key=f'urls/{code}.json',
            Body=json.dumps(payload),
            ContentType='application/json'
        )

        return response(200, {
            'short_url': f'{BASE_URL}/{code}',
            'code': code
        })

    except Exception as e:
        return response(500, {'error': str(e)})

def response(status, body):
    return {
        'statusCode': status,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body)
    }
