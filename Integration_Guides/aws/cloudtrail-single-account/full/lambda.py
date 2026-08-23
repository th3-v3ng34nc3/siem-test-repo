import boto3
import gzip
import json
import io
import urllib.request
import logging
import os
import base64
import ssl

# Initialize logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

def get_env_config():
    return {
        "target_url": os.environ.get("TARGET_URL"),
        "chunk_size": int(os.environ.get("CHUNK_SIZE_LIMIT", 3 * 1024 * 1024)),
        "line_limit": int(os.environ.get("LINE_LIMIT", 1000)),
        "user": os.environ.get("BASIC_USER"),
        "password": os.environ.get("BASIC_PASS"),
        "insecure_tls": os.environ.get("INSECURE_TLS_SKIP", "false").lower() == "true"
    }

def handler(event, context):
    config = get_env_config()
    if not config["target_url"]:
        logger.error("TARGET_URL environment variable is missing.")
        return {"statusCode": 500}

    # Setup SSL Context for insecure skip
    ssl_context = None
    if config["insecure_tls"]:
        logger.warning("SSL verification is disabled (INSECURE_TLS_SKIP=true)")
        ssl_context = ssl._create_unverified_context()

    for record in event.get('Records', []):
        bucket = record.get('s3', {}).get('bucket', {}).get('name')
        key = record.get('s3', {}).get('object', {}).get('key')
        
        if not bucket or not key:
            continue

        try:
            # 1. Download and decompress entirely into memory
            response = s3.get_object(Bucket=bucket, Key=key)
            with gzip.GzipFile(fileobj=response['Body']) as gf:
                content = gf.read() # This loads the whole decompressed file into RAM
            
            # 2. Parse the JSON
            data = json.loads(content.decode('utf-8'))
            
            # 3. Process the 'Records' list
            records_list = data.get('Records', [])
            logger.info(f"Loaded {len(records_list)} records from {key}")
            
            current_chunk = []
            current_size = 0
            
            for item in records_list:                
                # Convert back to JSON string for chunking
                item_str = json.dumps(item) + "\n"
                item_bytes = item_str.encode('utf-8')
                item_size = len(item_bytes)
                
                # Check if we need to send the current batch
                if (current_size + item_size > config["chunk_size"]) or (len(current_chunk) >= config["line_limit"]):
                    if current_chunk:
                        send_data("".join(current_chunk), config, ssl_context)
                        current_chunk, current_size = [], 0
                
                current_chunk.append(item_str)
                current_size += item_size
            
            # Flush final batch
            if current_chunk:
                send_data("".join(current_chunk), config, ssl_context)

        except Exception as e:
            logger.error(f"Error processing {key}: {str(e)}")
            continue

    return {"statusCode": 200}

def send_data(payload, config, ssl_context):
    data_bytes = payload.encode('utf-8')
    headers = {'Content-Type': 'application/x-ndjson'}
    
    if config["user"] and config["password"]:
        auth_str = f"{config['user']}:{config['password']}"
        encoded_auth = base64.b64encode(auth_str.encode('ascii')).decode('ascii')
        headers['Authorization'] = f"Basic {encoded_auth}"
        
    req = urllib.request.Request(config["target_url"], data=data_bytes, headers=headers, method='POST')
    
    try:
        with urllib.request.urlopen(req, timeout=15, context=ssl_context) as response:
            logger.info(f"Successfully posted {len(data_bytes)} bytes. Status: {response.getcode()}")
    except Exception as e:
        logger.error(f"HTTP Post failed: {str(e)}")
        raise e