import json
import boto3
import os

s3 = boto3.client('s3')
BUCKET = os.environ.get('S3_BUCKET', 'my-url-shortener-bucket')

def lambda_handler(event, context):
    try:
        code = event.get('pathParameters', {}).get('code', '').strip()

        if not code:
            return response(400, 'Missing short code.')

        try:
            obj = s3.get_object(Bucket=BUCKET, Key=f'urls/{code}.json')
            payload = json.loads(obj['Body'].read())
        except s3.exceptions.NoSuchKey:
            return response(404, 'Short URL not found.')

        original_url = payload.get('original_url')
        if not original_url:
            return response(500, 'Corrupted mapping.')

        # Increment hit counter (fire and forget)
        try:
            payload['hits'] = payload.get('hits', 0) + 1
            s3.put_object(
                Bucket=BUCKET,
                Key=f'urls/{code}.json',
                Body=json.dumps(payload),
                ContentType='application/json'
            )
        except Exception:
            pass  # Don't fail redirect if counter update fails

        return {
            'statusCode': 301,
            'headers': {
                'Location': original_url,
                'Access-Control-Allow-Origin': '*'
            },
            'body': ''
        }

    except Exception as e:
        return response(500, str(e))

def response(status, message):
    return {
        'statusCode': status,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'error': message})
    }
