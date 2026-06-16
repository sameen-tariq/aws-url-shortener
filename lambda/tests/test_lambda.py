import json
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../shorten'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../redirect'))

def test_generate_code():
    from lambda_shorten import generate_code
    code = generate_code()
    assert len(code) == 6

def test_shorten_missing_url():
    from lambda_shorten import lambda_handler
    event = {"body": json.dumps({"url": ""})}
    result = lambda_handler(event, None)
    assert result["statusCode"] == 400

def test_redirect_missing_code():
    from lambda_redirect import lambda_handler
    event = {"pathParameters": {"code": ""}}
    result = lambda_handler(event, None)
    assert result["statusCode"] == 400
