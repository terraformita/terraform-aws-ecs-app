import jwt
import requests
import base64
import json
import boto3
import os
from base import Base

# Defaults and arguments
logger = Base().get_logger()

# Defaults and arguments
standalone_run = os.environ.get('STANDALONE_RUN', False)
region = os.environ.get('REGION', "us-east-1")

PUB_KEY_URL = "https://public-keys.auth.elb.{region}.amazonaws.com/{kid}"

def lambda_handler(event, context):
    # Our default response: 401 - Unauthorized
    response = {
        "statusCode": 401,
        "statusDescription": "Unauthorized",
        "isBase64Encoded": False,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": ""
    }

    # Retrieve load balancer JWT headers from event header
    data = get_event_header(event, 'x-amzn-oidc-data', 'OIDC Data Header')
    access_token = get_event_header(event, 'x-amzn-oidc-accesstoken', 'OIDC Access Token')

    if data is None or access_token is None:
        return response

    # Decode JWT header
    try:
        encoded_jwt = data
        jwt_headers = encoded_jwt.split('.')[0]

        decoded_jwt_headers = base64.b64decode(jwt_headers)
        decoded_jwt_headers = decoded_jwt_headers.decode("utf-8")
        decoded_json = json.loads(decoded_jwt_headers)

        logger.debug( "Decoded JWT header", extra={ 'data': { 'jwt_header': decoded_json }})

        kid = decoded_json['kid']
        alg = decoded_json['alg']
    except Exception:
        logger.error(
            "Can not decode incoming JWT token to continue authorization process. ", exc_info=True)
        return response

    # Retrieve Public Key to decode JWT claims
    try:
        url = PUB_KEY_URL.format(region=region, kid=kid)
        req = requests.get(url, timeout=5)
        pub_key = req.text
    except Exception:
        logger.error("Unable to retrieve public key to decode JWT token. ", exc_info=True)
        return response

    # Decode JWT claims
    try:
        payload = jwt.decode(encoded_jwt, pub_key, algorithms=[alg])
        logger.debug("Decoded JWT payload", extra={ 'data': { 'jwt_payload': payload }})
    except Exception:
        logger.error("Can not decode incoming JWT token. ", exc_info=True)
        return response

    # Return successful response
    response['statusCode'] = 200
    response['statusDescription'] = 'OK'
    response['body'] = json.dumps({
        "access_token": access_token,
        "user_info": payload
    })
    return response

def get_event_header(event, key: str, value_type: str):
    try:
        value = event['headers'][key]
    except KeyError:
        logger.error(f"Can not get {value_type} from the incoming request.", exc_info=True)
        logger.info("Check if multi-value headers are ON? They are not supported by this lambda.")
        return None

    return value

# Standalone execution
def standalone():
    print("""
Usage: STANDALONE_RUN=1 <other env variables> lambda_handler.py

Other env variables:
    """)
    jwt_input = input("Enter JWT: ")
    print(lambda_handler({
        'headers': {
            'x-amzn-oidc-data': jwt_input,
        }
    }, None))

if standalone_run == True:
    standalone()
